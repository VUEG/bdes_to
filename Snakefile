import fiona
import geopandas as gpd
import gdal
import numpy as np
import numpy.ma as ma
import os
import pandas as pd
import rasterio
import rasterio.tools.mask
import sys
from importlib.machinery import SourceFileLoader
from rasterstats import zonal_stats


## LOAD MODULES --------------------------------------------------------------
utils = SourceFileLoader("lib.utils", "src/00_lib/utils.py").load_module()
spatutils = SourceFileLoader("lib.spatutils", "src/00_lib/spatutils.py").load_module()
cutter = SourceFileLoader("lib.cutter", "src/01_pre_processing/cutter.py").load_module()
similarity = SourceFileLoader("results.similarity", "src/03_post_processing/similarity.py").load_module()

## GLOBALS --------------------------------------------------------------------

# Analysis extent
PROJECT_EXTENT = {"bottom": 1000000.0, "left": 2000000.0, "right": 6526000.0,
                  "top": 5410000.0}
# EPSG for project
PROJECT_CRS = 3035

# Project resolution in units of PROJECT_CRS
PROJECT_RES = 100

# Offset the bounds given in extent_yml. Values are in order
# (left, bottom, right, top) and interpreted in the CRS units. values
# are added to bounds given by PROJECT_EXTENT
OFFSET = (100000, 100000, 0, 0)
# Which eurostat countries are included in the processed output? The
# following countries have been removed:
# "CY", "CH", "IS", "HR", "NO", "ME", "MT", "MK", "TR", "LI"
PROJECT_COUNTRIES = ["AT", "BE", "BG", "CZ", "DE", "DK", "ES", "EL", "EE",
                     "FR", "FI", "IT", "HU", "IE", "NL", "LU", "LT",
                     "LV", "PL", "SE", "RO", "PT", "SK", "SI", "UK"]

# Load the content of the data manifest file into a DataManager object.
dm = utils.DataManager("data/data_manifest.yml")

external_data = "data/external"
# Final feature data
feature_data = "data/processed/features"
beehub_url = "https://beehub.nl/environmental-geography-group"

# Define source and desination datasets. NOTE: data/Snakefile must be run
# before this Snakefile will work
DATADRYAD_SRC_DATASETS = [url.replace(beehub_url, external_data) for url in dm.get_resources(provider="datadryad", full_path=True)]

EEA_SRC_DATASETS = [url.replace(beehub_url, external_data) for url in dm.get_resources(provider="eea", full_path=True)]

JRC_SRC_DATASETS = [url.replace(beehub_url, external_data) for url in dm.get_resources(provider="jrc", full_path=True)]

# Get specific NUTS collections from Eurostat
NUTS_LEVEL0_DATA = [url.replace(beehub_url, external_data) for url in dm.get_resources(collection="nuts_level0", full_path=True)]
NUTS_LEVEL2_DATA = [url.replace(beehub_url, external_data) for url in dm.get_resources(collection="nuts_level2", full_path=True)]

PROVIDE_SRC_DATASETS = [url.replace(beehub_url, external_data) for url in dm.get_resources(provider="provide", full_path=True)]

# UDR collection "european_tetrapods" is already correctly formatted, place
# it directly to "processed/features"
UDR_SRC_DATASETS = [url.replace(beehub_url, external_data) for url in dm.get_resources(provider="udr", full_path=True)]

# Construct lists for processed BD and ES datasets
BD_DST_DATASETS = [url.replace(beehub_url, feature_data) for url in dm.get_resources(category="biodiversity", full_path=True)]
ES_DST_DATASETS = [url.replace(beehub_url, feature_data) for url in dm.get_resources(category="ecosystemservices", full_path=True)]

ALL_SRC_DATASETS = DATADRYAD_SRC_DATASETS + PROVIDE_SRC_DATASETS + JRC_SRC_DATASETS + UDR_SRC_DATASETS

# Let's build weight vectors needed for the weighted analysis variants

# Set the weight of each feature in category "biodiversity" to 1.0 and the
# weight of each feature in "ecosystemservices" to sum(bd_wights) / n_es.
# NOTE: the above weighting scheme is needed to avoid small weights values that
# e.g. 1.0 / n_bd would produce. For some reason the ILP implementation
# doesn't like small weight values
# (see: https://github.com/VUEG/priocomp/issues/8)
# NOTE: the order matters here greatly: ecosystem services
# need to come first.
N_ES = dm.count(category="ecosystemservices")
N_BD = dm.count(category="biodiversity")
WEIGHTS = [N_BD / N_ES] * N_ES + [1.0] * N_BD

# Define a group of rasters that need to be rescaled (normalized) for the
# following reasons:
#
# carbon_sequestration.tif = Values can have negative values (area is a carbon
#                            source instead of sink)
NORMALIZED_DATASETS = {"carbon_sequestration.tif":
                       "carbon_sequestration_rescaled.tif"}


# PROJECT RULES ----------------------------------------------------------------

rule all:
    input:
        ""

# ## Data pre-processing ---------------------------------------------------------

rule preprocess_nuts_level0_data:
    input:
        shp=NUTS_LEVEL0_DATA
    output:
        reprojected=temp([path.replace("external", "interim/reprojected") for path in NUTS_LEVEL0_DATA]),
        enhanced=temp([path.replace("external", "interim/enhanced") for path in NUTS_LEVEL0_DATA]),
        processed=[path.replace("external", "processed") for path in NUTS_LEVEL0_DATA]
    log:
        "logs/preprocess_nuts_level0_data.log"
    message:
        "Pre-processing NUTS level 0 data..."
    run:
        llogger = utils.get_local_logger("pprocess_nuts0", log[0])
        # Read in the bounds as used in harmonize_data rule
        bleft = PROJECT_EXTENT["left"] + OFFSET[0]
        bbottom = PROJECT_EXTENT["bottom"] + OFFSET[1]
        bright = PROJECT_EXTENT["right"] + OFFSET[2]
        btop = PROJECT_EXTENT["top"] + OFFSET[3]
        bounds = "{0} {1} {2} {3}".format(bleft, bbottom, bright, btop)
        # Reproject to EPSG:3035 from EPSG:4258
        input_shp = utils.pick_from_list(input.shp, ".shp")
        reprojected_shp = utils.pick_from_list(output.reprojected, ".shp")
        cmd_str = 'ogr2ogr {0} -t_srs "EPSG:{1}" {2}'.format(reprojected_shp, PROJECT_CRS, input_shp)
        shell(cmd_str)
        llogger.info("Reprojected NUTS level 0 data from EPSG:4258 to EPSG:3035")
        llogger.debug(cmd_str)

        # NUTS 0 data has "NUTS_ID" field, but it's character. Convert to
        # integer for raserization
        enhanced_shp = utils.pick_from_list(output.enhanced, ".shp")
        with fiona.drivers():
            with fiona.open(reprojected_shp) as source:
                meta = source.meta
                meta['schema']['geometry'] = 'Polygon'
                # Insert new fields
                meta['schema']['properties']['ID'] = 'int'
                meta['schema']['properties']['mask'] = 'int'

                ID = 1
                with fiona.open(enhanced_shp, 'w', **meta) as sink:
                    # Loop over features
                    for f in source:
                        f['properties']['ID'] = ID
                        ID += 1
                        # Create a mask ID (same for each feature) that can
                        # later be used in creating a mask.
                        f['properties']['mask'] = 1
                        # Write the record out.
                        sink.write(f)

        # Clip shapefile using ogr2ogr, syntax:
        # ogr2ogr output.shp input.shp -clipsrc <left> <bottom> <right> <top>
        processed_shp = utils.pick_from_list(output.processed, ".shp")
        # Do 2 things at the same time:
        #  1. Select a subset of counties (defined by params.countries)
        #  2. Clip output to an extent (given by bounds)
        # Build the -where clause for ogr2ogr
        where_clause = "NUTS_ID IN ({})".format(", ".join(["'" + item + "'" for item in PROJECT_COUNTRIES]))
        shell('ogr2ogr -where "{where_clause}" {processed_shp} {enhanced_shp} -clipsrc {bounds}')
        llogger.debug("Clipped NUTS data to analysis bounds: {}".format(bounds))
        llogger.debug("Selected only a subset of eurostat countries:")
        llogger.debug(" " + ", ".join(PROJECT_COUNTRIES))
        llogger.debug("Resulting file: {}".format(processed_shp))

rule preprocess_nuts_level2_data:
    input:
        shp=NUTS_LEVEL2_DATA
    output:
        reprojected=temp([path.replace("external", "interim/reprojected") for path in NUTS_LEVEL2_DATA]),
        clipped=temp([path.replace("external", "interim/clipped") for path in NUTS_LEVEL2_DATA]),
        processed=[path.replace("external", "processed") for path in NUTS_LEVEL2_DATA]
    log:
        "logs/preprocess_nuts_level2_data.log"
    message:
        "Pre-processing NUTS level 2 data..."
    run:
        llogger = utils.get_local_logger("pprocess_nuts2", log[0])
        # Read in the bounds as used in harmonize_data rule
        bleft = PROJECT_EXTENT["left"] + OFFSET[0]
        bbottom = PROJECT_EXTENT["bottom"] + OFFSET[1]
        bright = PROJECT_EXTENT["right"] + OFFSET[2]
        btop = PROJECT_EXTENT["top"] + OFFSET[3]
        bounds = "{0} {1} {2} {3}".format(bleft, bbottom, bright, btop)
        # Reproject to EPSG:3035 from EPSG:4258 and clip
        input_shp = utils.pick_from_list(input.shp, ".shp")
        reprojected_shp = utils.pick_from_list(output.reprojected, ".shp")
        cmd_str = 'ogr2ogr {0} -t_srs "EPSG:{1}" {2}'.format(reprojected_shp, PROJECT_CRS, input_shp)
        shell(cmd_str)
        llogger.debug("Reprojected NUTS level 2 data from EPSG:4258 to EPSG:3035")
        llogger.debug(cmd_str)

        # Clip shapefile using ogr2ogr, syntax:
        # ogr2ogr output.shp input.shp -clipsrc <left> <bottom> <right> <top>
        clipped_shp = utils.pick_from_list(output.clipped, ".shp")
        # Clip output to an extent (given by bounds)
        shell('ogr2ogr {clipped_shp} {reprojected_shp} -clipsrc {bounds}')

        # The Pre-processing steps need to be done:
        #  1. Tease apart country code from field NUTS_ID
        #  2. Create a running ID field that can be used as value in the
        #     rasterized version
        processed_shp = utils.pick_from_list(output.processed, ".shp")
        with fiona.drivers():
            with fiona.open(clipped_shp) as source:
                meta = source.meta
                meta['schema']['geometry'] = 'Polygon'
                # Insert new fields
                meta['schema']['properties']['ID'] = 'int'
                meta['schema']['properties']['country'] = 'str'

                ID = 1
                with fiona.open(processed_shp, 'w', **meta) as sink:
                    # Loop over features
                    for f in source:
                        # Check the country code part of NUTS_ID (2 first
                        # charatcters). NOTE: we're effectively doing filtering
                        # here.
                        country_code = f['properties']['NUTS_ID'][0:2]
                        if country_code in PROJECT_COUNTRIES:
                            f['properties']['ID'] = ID
                            ID += 1
                            f['properties']['country'] = country_code
                            # Write the record out.
                            sink.write(f)

        llogger.debug("Clipped NUTS level 2 data to analysis bounds: {}".format(bounds))
        llogger.debug("Selected only a subset of eurostat countries:")
        llogger.debug(" " + ", ".join(PROJECT_COUNTRIES))
        llogger.debug("Resulting file: {}".format(processed_shp))

rule rasterize_nuts_level0_data:
    # Effectively, create a 1) land mask and 2) common data mask
    input:
        rules.preprocess_nuts_level0_data.output.processed
    output:
        land_mask=utils.pick_from_list(rules.preprocess_nuts_level0_data.output.processed, ".shp").replace(".shp", ".tif"),
        data_mask=utils.pick_from_list(rules.preprocess_nuts_level0_data.output.processed, ".shp").replace(".shp", "_data_mask.tif"),
    log:
        "logs/rasterize_nuts_level0_data.log"
    message:
        "Rasterizing NUTS level 0 data..."
    run:
        llogger = utils.get_local_logger("rasterize_nuts0", log[0])
        input_shp = utils.pick_from_list(input, ".shp")
        layer_shp = os.path.basename(input_shp).replace(".shp", "")

        # Construct extent
        bounds = "{0} {1} {2} {3}".format(PROJECT_EXTENT["left"],
                                          PROJECT_EXTENT["bottom"],
                                          PROJECT_EXTENT["right"],
                                          PROJECT_EXTENT["top"])
        # 1) Rasterize land mask
        cmd_str = "gdal_rasterize -l {} ".format(layer_shp) + \
                  "-a ID -tr 1000 1000 -te {} ".format(bounds) + \
                  "-ot Int16 -a_nodata -32768 -co COMPRESS=DEFLATE " + \
                  "{0} {1}".format(input_shp, output.land_mask)
        llogger.debug(cmd_str)
        for line in utils.process_stdout(shell(cmd_str, read=True)):
            llogger.debug(line)
        # 2) Rasterize common data mask
        cmd_str = "gdal_rasterize -l {} ".format(layer_shp) + \
                  "-a mask -tr 1000 1000 -te {} ".format(bounds) + \
                  "-ot Int8 -a_nodata -128 -co COMPRESS=DEFLATE " + \
                  "{0} {1}".format(input_shp, output.data_mask)
        llogger.debug(cmd_str)
        for line in utils.process_stdout(shell(cmd_str, read=True)):
            llogger.debug(line)

rule rasterize_nuts_level2_data:
    input:
        rules.preprocess_nuts_level2_data.output.processed
    output:
        utils.pick_from_list(rules.preprocess_nuts_level2_data.output.processed, ".shp").replace(".shp", ".tif")
    log:
        "logs/rasterize_nuts_level2_data.log"
    message:
        "Rasterizing NUTS level 2 data..."
    run:
        llogger = utils.get_local_logger("rasterize_nuts2", log[0])
        input_shp = utils.pick_from_list(input, ".shp")
        layer_shp = os.path.basename(input_shp).replace(".shp", "")

        # Construct extent
        bounds = "{0} {1} {2} {3}".format(PROJECT_EXTENT["left"],
                                          PROJECT_EXTENT["bottom"],
                                          PROJECT_EXTENT["right"],
                                          PROJECT_EXTENT["top"])
        # Rasterize
        cmd_str = "gdal_rasterize -l {} ".format(layer_shp) + \
                  "-a ID -tr 1000 1000 -te {} ".format(bounds) + \
                  "-ot Int16 -a_nodata -32768 -co COMPRESS=DEFLATE " + \
                  "{0} {1}".format(input_shp, output[0])
        llogger.debug(cmd_str)
        for line in utils.process_stdout(shell(cmd_str, read=True)):
            llogger.debug(line)

rule clip_udr_data:
    input:
        external=UDR_SRC_DATASETS,
        clip_shp=utils.pick_from_list(rules.preprocess_nuts_level0_data.output.processed, ".shp")
    output:
        clipped=[path.replace("external", "processed/features") for path in UDR_SRC_DATASETS]
    log:
        "logs/clip_udr_data.log"
    message:
        "Clipping UDR data..."
    run:
        llogger = utils.get_local_logger("clip_udr_data", log[0])
        nsteps = len(input.external)
        for i, s_raster in enumerate(input.external):
            # Target raster
            clipped_raster = s_raster.replace("external", "processed/features")
            prefix = utils.get_iteration_prefix(i+1, nsteps)

            llogger.info("{0} Clipping dataset {1}".format(prefix, s_raster))
            llogger.debug("{0} Target dataset {1}".format(prefix, clipped_raster))
            # Clip data. NOTE: UDR species rasters do not have a SRS defined,
            # but they are in EPSG:3035
            cmd_str = 'gdalwarp -s_srs EPSG:3035 -t_srs EPSG:3035 -cutline {0} {1} {2} -co COMPRESS=DEFLATE'.format(input.clip_shp, s_raster, clipped_raster)
            for line in utils.process_stdout(shell(cmd_str, read=True), prefix=prefix):
                llogger.debug(line)

rule harmonize_data:
    input:
        external=DATADRYAD_SRC_DATASETS+PROVIDE_SRC_DATASETS+JRC_SRC_DATASETS,
        like_raster=[path for path in DATADRYAD_SRC_DATASETS if "woodprod_average" in path][0],
        clip_shp=utils.pick_from_list(rules.preprocess_nuts_level0_data.output.processed, ".shp")
    output:
        # NOTE: UDR_SRC_DATASETS do not need to processed
        warped=temp([path.replace("external", "interim/warped") for path in DATADRYAD_SRC_DATASETS+PROVIDE_SRC_DATASETS+JRC_SRC_DATASETS if not path.endswith(".zip")]),
        harmonized=[path.replace("external", "processed/features") for path in DATADRYAD_SRC_DATASETS+PROVIDE_SRC_DATASETS+JRC_SRC_DATASETS if not path.endswith(".zip")],
        output_fz="data/processed/features_flow_zones/provide"
    log:
        "logs/harmonize_data.log"
    message:
        "Harmonizing datasets..."
    run:
        llogger = utils.get_local_logger("harmonize_data", log[0])
        nsteps = len(input.external)
        for i, s_raster in enumerate(input.external):

            # The assumption is that zips don't need anything else but
            # extraction
            if s_raster.endswith(".zip"):
                target_dir = s_raster.replace("external", "processed/features_flow_zones")
                target_dir = os.path.dirname(target_dir)
                # Get rid of the last path component to avoid repetition
                target_dir = os.path.sep.join(target_dir.split(os.path.sep)[:-1])
                if not os.path.exists(target_dir):
                    os.mkdir(target_dir)
                prefix = utils.get_iteration_prefix(i+1, nsteps)
                llogger.info("{0} Unzipping dataset {1}".format(prefix, s_raster))
                shell("unzip -o {} -d {} >& {}".format(s_raster, target_dir, log[0]))
            else:
                ## WARP
                # Target raster
                warped_raster = s_raster.replace("external", "interim/warped")
                # No need to process the snap raster, just copy it
                prefix = utils.get_iteration_prefix(i+1, nsteps)
                if s_raster == input.like_raster:
                    llogger.info("{0} Copying dataset {1}".format(prefix, s_raster))
                    llogger.debug("{0} Target dataset {1}".format(prefix, warped_raster))
                    ret = shell("cp {s_raster} {warped_raster}", read=True)
                else:
                    llogger.info("{0} Warping dataset {1}".format(prefix, s_raster))
                    llogger.debug("{0} Target dataset {1}".format(prefix, warped_raster))
                    ret = shell("rio warp " + s_raster + " --like " + input.like_raster + \
                                " " + warped_raster + " --dst-crs " + str(PROJECT_CRS) + \
                                " --res " + str(PROJECT_RES) + \
                                " --co 'COMPRESS=DEFLATE' --threads {threads}")
                for line in utils.process_stdout(ret, prefix=prefix):
                    llogger.debug(line)
                ## CLIP
                harmonized_raster = warped_raster.replace("data/interim/warped", "data/processed/features")
                llogger.info("{0} Clipping dataset {1}".format(prefix, warped_raster))
                llogger.debug("{0} Target dataset {1}".format(prefix, harmonized_raster))
                cmd_str = "gdalwarp -cutline {0} {1} {2} -co COMPRESS=DEFLATE".format(input.clip_shp, warped_raster, harmonized_raster)
                for line in utils.process_stdout(shell(cmd_str, read=True), prefix=prefix):
                    llogger.debug(line)

                # Rescale (normalize) dataset if needed
                org_raster = os.path.basename(harmonized_raster)
                if org_raster in NORMALIZED_DATASETS.keys():
                    rescaled_raster = harmonized_raster.replace(org_raster,
                                                                NORMALIZED_DATASETS[org_raster])
                    llogger.info("{0} Rescaling dataset {1}".format(prefix, harmonized_raster))
                    llogger.debug("{0} Target dataset {1}".format(prefix, rescaled_raster))
                    spatutils.rescale_raster(harmonized_raster, rescaled_raster,
                                             method="normalize",
                                             only_positive=True, verbose=False)
                    os.remove(harmonized_raster)
                    llogger.debug("{0} Renaming dataset {1} to {2}".format(prefix, rescaled_raster, harmonized_raster))
                    os.rename(rescaled_raster, harmonized_raster)
                    harmonized_raster = rescaled_raster


rule process_flowzones:
    input:
        src=["data/processed/features/provide/cultural_landscape_index_agro//cultural_landscape_index_agro.tif",
             "data/processed/features/provide/cultural_landscape_index_forest/cultural_landscape_index_forest.tif"],
        flow_zone_units=utils.pick_from_list(rules.preprocess_nuts_level0_data.output.processed, ".shp")
    output:
        "data/processed/features_flow_zones/provide/cultural_landscape_index_agro_flow_zones",
        "data/processed/features_flow_zones/provide/cultural_landscape_index_forest_flow_zones"
    log:
        "logs/process_flowzones_data.log"
    threads: 4
    message:
        "Processing flow zones using {threads} cores..."
    run:
        llogger = utils.get_local_logger("process_flowzones", log[0])

        for in_raster, outdir in zip(input.src, output):
            cmd_str = "src/01_pre_processing/cutter.py {} {} {} -f {} -c {}".format(in_raster,
                                                                                    input.flow_zone_units,
                                                                                    outdir,"ID",
                                                                                        threads)
            print(cmd_str)
            for line in utils.process_stdout(shell(cmd_str, read=True)):
                llogger.debug(line)

rule calculate_flowzone_weights:
    input:
        cli_agro="data/processed/features/provide/cultural_landscape_index_agro/cultural_landscape_index_agro.tif",
        cli_forest="data/processed/features/provide/cultural_landscape_index_forest/cultural_landscape_index_forest.tif",
        flow_zone_units=utils.pick_from_list(rules.preprocess_nuts_level0_data.output.processed, ".shp")
    output:
        cli_agro="data/WeightsTableCLIagro.txt",
        cli_forest="data/WeightsTableCLIforest.txt"
    log:
        "logs/calculate_flowzone_weights.log"
    message:
        "Calculating flowzone weights..."
    run:
        llogger = utils.get_local_logger("calculate_flowzone_weights", log[0])

        llogger.info(" [1/2] Calculating zonal stats for {}".format(input.cli_agro))
        stats = zonal_stats(input.flow_zone_units, input.cli_agro,
                            stats=['sum'])
        print(stats)


## Set up, run and post-process analyses --------------------------------------

# # Zonation ---------------------------------------------------------------------
#
# rule generate_zonation_project:
#     input:
#         expand("data/processed/features/provide/{dataset}/{dataset}.tif", dataset=PROVIDE_DATASETS) + \
#         expand("data/processed/features/datadryad/forest_production_europe/{dataset}.tif", dataset=DATADRYAD_DATASETS),
#         "data/processed/nuts/NUTS_RG_01M_2013/level2/NUTS_RG_01M_2013_level2_subset.tif"
#     output:
#         "analyses/zonation/priocomp"
#     message:
#         "Generating Zonation project..."
#     script:
#         # NOTE: Currently there's a lot of things hardcoded here...
#         "src/zonation/01_create_zonation_project.R"

## Compare results ------------------------------------------------------------

## Auxiliary operations -----------------------------------------------------

rule generate_range_data:
    input:
        "data/data_manifest.yml"
    output:
        csv="data/feature_ranges.csv"
    log:
        "logs/generate_range_data.log"
    message:
        "Generating feature ranges..."
    run:
        llogger = utils.get_local_logger("generate_range_data", log[0],
                                         debug=True)

        range_stats = pd.DataFrame({"feature": [], "count": [], "sum": [],
                                    "q25_ol": [], "mean_ol": [],
                                    "median_ol": [], "q75_ol": []})

        features = ES_DST_DATASETS + BD_DST_DATASETS
        for i, feature in enumerate(features):
            prefix = utils.get_iteration_prefix(i+1, len(features))

            llogger.info("{} Processing {}".format(prefix, feature))

            feature_stats = spatutils.get_range_size(feature, logger = llogger)
            range_stats = pd.concat([range_stats, feature_stats])

        llogger.info(" Saving results to {}".format(output.csv))
        range_stats.to_csv(output.csv, columns=["feature", "count", "sum",
                                                "q25_ol", "mean_ol",
                                                "median_ol", "q75_ol"],
                                                index=False)
