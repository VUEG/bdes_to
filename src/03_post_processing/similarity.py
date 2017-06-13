#!/usr/bin/env python3
# -*- coding: utf-8 -*-
""" Functions and utilities comparing raster and vector similarities.

Module can be used alone or as part of Snakemake workflow.
"""
import logging
import rasterio
import geopandas as gpd
import pandas as pd
import numpy as np
import numpy.ma as ma

from importlib.machinery import SourceFileLoader
from scipy.spatial.distance import jaccard
from scipy.stats import kendalltau
from timeit import default_timer as timer

utils = SourceFileLoader("lib.utils", "src/00_lib/utils.py").load_module()


def compute_jaccard(x, y, x_min=0.0, x_max=1.0, y_min=0.0, y_max=1.0,
                    warn_uneven=True, limit_tolerance=4, disable_checks=False):
    """Calculate the Jaccard index (Jaccard similarity coefficient).

    The Jaccard coefficient measures similarity between sample sets, and is
    defined as the size of the intersection divided by the size of the union of
    the sample sets. The Jaccard coefficient can be calculated for a subset of
    rasters provided by using the threshold argument.

    Min and max values must be provided for both RasterLayer objects x
    and y. Method can be used with RasterLayers of any value range, but
    the defaults [0.0, 1.0] are geared towards comparing Zonation rank priority
    rasters. Limits provided are inclusive.

    :param x ndarray object.
    :param y ndarray object.
    :param x_min Numeric minimum threshold value for x to be used
                 (default 0.0).
    :param x_max Numeric maximum threshold value for x to be used
                 (default 1.0).
    :param y_min Numeric minimum threshold value for y to be used
                 (default 0.0).
    :param y_max Numeric maximum threshold value for y to be used
                 (default 1.0).
    :param warn_uneven Boolean indicating whether a warning is raised if the
                       compared raster coverages are very (>20x) uneven.
    :param limit_tolerance integer values that defines to which precision x and
                           y limits are rounded to. This helps e.g. with values
                           that close to 0 but not quite 0 (default: 4, i.e.
                           round(x, 4)).
    :param disable_checks boolean indicating if the input limit values are
                          checked against the actual raster values in x and y.

    :return numeric value in [0, 1].
    """
    if not disable_checks:
        assert x_min >= np.round(np.min(x), limit_tolerance), "Min threshold smaller than computed min of x"
        assert x_max <= np.round(np.max(x), limit_tolerance), "Max threshold greater than computed max of x"
        assert x_min < x_max, "Min threshold for x larger to max threshold"
        assert y_min >= np.round(np.min(y), limit_tolerance), "Min threshold smaller than computed min of y"
        assert y_max <= np.round(np.max(y), limit_tolerance), "Max threshold greater than computed max of y"
        assert y_min < y_max, "Min threshold for y larger to max threshold"

    # Get the values according to the limits provided
    x_bin = (x >= x_min) & (x <= x_max)
    y_bin = (y >= y_min) & (y <= y_max)

    if warn_uneven:
        x_size = np.sum(x_bin)
        y_size = np.sum(y_bin)
        # Sort from smaller to larger
        sizes = np.sort([x_size, y_size])
        if sizes[1] / sizes[0] > 20:
            print("WARNING: The extents of raster values above the "
                  "threshhold differ more than 20-fold: Jaccard coefficient " +
                  "may not be informative.")

    # Compute the Jaccard-Needham dissimilarity between two boolean 1-D arrays
    # and subtract from 1 to get the Jaccard index
    return 1 - jaccard(x_bin.flatten(), y_bin.flatten())


def cross_correlation(input_rasters, verbose=False, logger=None):
    """ Calculate Kendall tau rank correlation between all the inpur rasters.

    Input rasters are read in as masked arrays and all cells that are NoData
    are discarded. This way, only the values of informative cells are passed
    on to scipy.stats.kendalltau() which makes things faster. The assumption is
    that all rasters exactly match on which cells have values. An intersection
    of both rasters' masks is used to define informative cells.

    :param input_rasters list of input raster paths.
    :param verbose: Boolean indicating how much information is printed out.
    :param logger: logger object to be used.

    :return Pandas Dataframe with rank correlation information.
    """
    # 1. Setup  --------------------------------------------------------------

    all_start = timer()

    if not logger:
        logging.basicConfig()
        llogger = logging.getLogger('cross_correlation')
        llogger.setLevel(logging.DEBUG if verbose else logging.INFO)
    else:
        llogger = logger

    # Check the inputs
    assert len(input_rasters) > 1, "More than one input rasters are needed"

    # 2. Calculations --------------------------------------------------------

    llogger.info(" [** COMPUTING KENDALL TAU RANK CORRELATIONS **]")

    all_correlations = pd.DataFrame({"feature1": [], "feature2": [],
                                     "tau": [], "pvalue": []})
    n_rasters = len(input_rasters)
    # Generate counter information for all the computations. The results
    # matrix is always diagonally symmetrical.
    n_computations = int((n_rasters * n_rasters - n_rasters) / 2)
    no_computation = 1

    for i in range(0, n_rasters):
        raster1 = rasterio.open(input_rasters[i])
        raster1_src = raster1.read(1, masked=True)
        for j in range(i+1, n_rasters):
            raster2 = rasterio.open(input_rasters[j])
            raster2_src = raster2.read(1, masked=True)

            # Compute the intersection of the masks of both rasters and use
            # that as a value mask.
            value_mask = raster1_src.mask & raster2_src.mask
            # Then set the mask of both raster to the intersection mask
            raster1_src.mask = value_mask
            raster2_src.mask = value_mask

            # Inlude only cells with actual values
            raster1_values = ma.compressed(raster1_src)
            raster2_values = ma.compressed(raster2_src)
            prefix = utils.get_iteration_prefix(no_computation,
                                                n_computations)
            llogger.info(("{} Calculating correlation ".format(prefix) +
                          "between {} ".format(input_rasters[i]) +
                          "and {}".format(input_rasters[j])))
            # Compute Kendall's tau rank correlation
            tau, pvalue = kendalltau(raster1_values, raster2_values)
            llogger.debug("Tau: {0} (p-value: {1})".format(tau, pvalue))
            correlations = pd.DataFrame({"feature1": [input_rasters[i]],
                                         "feature2": [input_rasters[j]],
                                         "tau": [tau],
                                         "pvalue": [pvalue]})
            all_correlations = pd.concat([all_correlations, correlations])
            no_computation += 1

    all_correlations.index = np.arange(0, len(all_correlations.index), 1)

    all_end = timer()
    all_elapsed = round(all_end - all_start, 2)
    llogger.info(" [TIME] All processing took {} sec".format(all_elapsed))

    return all_correlations


def cross_jaccard(input_rasters, thresholds, verbose=False, logger=None):
    """ Calculate Jaccard coefficients between all the inpur rasters.

    This is a utility function that is intented to be used to compare
    fractions of the landscape.

    :param input_rasters list of input raster paths.
    :param thresholds vector of numeric tuples (x_min, x_max, y_min, y_max) values of thresholds.
    :param verbose: Boolean indicating how much information is printed out.
    :param logger: logger object to be used.
    :param ... additional arguments passed on to jaccard().

    :return Pandas Dataframe with Jaccard coefficients between all rasters.
    """
    # 1. Setup  --------------------------------------------------------------

    all_start = timer()

    if not logger:
        logging.basicConfig()
        llogger = logging.getLogger('cross_jaccard')
        llogger.setLevel(logging.DEBUG if verbose else logging.INFO)
    else:
        llogger = logger

    # Check the inputs
    assert len(input_rasters) > 1, "More than one input rasters are needed"
    assert len(thresholds) >= 1, "At least one tuple of thresholds is needed"

    # 2. Calculations --------------------------------------------------------

    llogger.info(" [** COMPUTING JACCARD INDICES **]")

    all_jaccards = pd.DataFrame({"feature1": [], "feature2": [],
                                 "threshold": [], "coef": []})
    n_rasters = len(input_rasters)
    # Generate counter information for all the computations. The results
    # matrix is always diagonally symmetrical.
    n_computations = int((n_rasters * n_rasters - n_rasters) / 2 * len(thresholds))
    no_computation = 1

    for threshold in thresholds:
        if len(threshold) != 4:
            llogger.error("Threshold tuple needs 4 values")
            next
        for i in range(0, n_rasters):
            x_min, x_max, y_min, y_max = threshold
            raster1 = rasterio.open(input_rasters[i])
            # To calculate the Jaccard index we are dealing with binary data
            # only. Avoid using masked arrays and replace NoData values with
            # zeros.
            raster1_nodata = raster1.nodata
            raster1_src = raster1.read(1)
            np.place(raster1_src, np.isclose(raster1_src, raster1_nodata), 0.0)
            for j in range(i+1, n_rasters):
                raster2 = rasterio.open(input_rasters[j])
                raster2_nodata = raster2.nodata
                raster2_src = raster2.read(1)
                np.place(raster2_src, np.isclose(raster2_src, raster2_nodata),
                         0.0)
                prefix = utils.get_iteration_prefix(no_computation,
                                                    n_computations)
                llogger.info(("{} Calculating Jaccard ".format(prefix) +
                              "index for [{0}, {1}] ".format(x_min, x_max) +
                              "in {} ".format(input_rasters[i]) +
                              "and, [{0}, {1}] ".format(y_min, y_max) +
                              "in {}".format(input_rasters[j])))

                coef = compute_jaccard(raster1_src, raster2_src,
                                       x_min=x_min, x_max=x_max,
                                       y_min=y_min, y_max=y_max)
                jaccards = pd.DataFrame({"feature1": [input_rasters[i]],
                                         "feature2": [input_rasters[j]],
                                         "threshold": [threshold],
                                         "coef": [coef]})
                all_jaccards = pd.concat([all_jaccards, jaccards])
                no_computation += 1

    all_jaccards.index = np.arange(0, len(all_jaccards.index), 1)

    all_end = timer()
    all_elapsed = round(all_end - all_start, 2)
    llogger.info(" [TIME] All processing took {} sec".format(all_elapsed))

    return all_jaccards


def compute_mcs(a, b):
    """ Compute MCS between vectors a and b.

    :param a numeric vector.
    :param b numeric vector.
    :return ndarray of computed MCS scores.
    """

    assert len(a) == len(b), "Vectors a and b must be of same length"
    N = len(a)
    # Create an array filled with -1s to store the MCS.
    mcs = 0
    nans = False

    for i in range(0, N):
        if np.isnan(a[i]) or np.isnan(b[i]):
            nans = True
        else:
            # If eiher a or b is 0, do nothing as division would fail
            if a[i] == 0.0 or b[i] == 0.0:
                pass
            else:
                abs_subs = np.abs(a[i] - b[i]) / np.max([a[i], b[i]])
                mcs += abs_subs
    if nans:
        print("WARNING: a and/or b contain NaNs")

    return mcs / N


def cross_mcs(input_vectors, value_fields, verbose=False, logger=None):
    """ Compute map comparison statistics between input vector features.

    MCS (Map Comparison Statistic) indicates the average difference between any
    pair of feature polygon values, expressed as a fraction of the highest
    value. MCS is calculated between each polygon in the input vector features
    and it is required (and checked) that all the inputs are based on the
    same vector feature.

    For another application of MCS, see:

    Schulp, C. J. E., Burkhard, B., Maes, J., Van Vliet, J., & Verburg, P. H.
    (2014). Uncertainties in Ecosystem Service Maps: A Comparison on the
    European Scale. PLoS ONE, 9(10), e109643.
    http://doi.org/10.1371/journal.pone.0109643

    :param input_vectors list of input vector paths.
    :param value_field list of String names indicating which fields contains
                       the values to be compared.
    :param verbose: Boolean indicating how much information is printed out.
    :param logger: logger object to be used.

    :return list of GeoPandas Dataframe with MCS between all rasters in field
            "mcs".
    """
    # 1. Setup  --------------------------------------------------------------

    all_start = timer()

    if not logger:
        logging.basicConfig()
        llogger = logging.getLogger('cross_mcs')
        llogger.setLevel(logging.DEBUG if verbose else logging.INFO)
    else:
        llogger = logger

    # Check the inputs
    assert len(input_vectors) > 1, "More than one input vector needed"
    assert len(value_fields) == len(input_vectors), "One value field per vector feature needed"

    # 2. Calculations --------------------------------------------------------

    llogger.info(" [** COMPUTING MCS SCORES **]")

    all_mcs = pd.DataFrame({"feature1": [], "feature2": [],
                            "mcs": []})
    n_vectors = len(input_vectors)
    # Generate counter information for all the computations. The results
    # matrix is always diagonally symmetrical.
    n_computations = int((n_vectors * n_vectors - n_vectors) / 2)
    no_computation = 1

    for i in range(0, n_vectors):
        # Read in the data as a GeoPandas dataframe
        vector1_path = input_vectors[i]
        vector1 = gpd.read_file(vector1_path)
        for j in range(i+1, n_vectors):
            vector2_path = input_vectors[j]
            vector2 = gpd.read_file(vector2_path)
            prefix = utils.get_iteration_prefix(no_computation,
                                                n_computations)
            llogger.info(("{} Calculating MCS ".format(prefix) +
                          "between {} ".format(vector1_path) +
                          "and {}".format(vector2_path)))

            a = vector1[value_fields[i]]
            b = vector2[value_fields[j]]

            mcs_value = compute_mcs(a, b)
            mcs = pd.DataFrame({"feature1": [vector1_path],
                                "feature2": [vector2_path],
                                "mcs": [mcs_value]})
            all_mcs = pd.concat([all_mcs, mcs])
            no_computation += 1

    all_mcs.index = np.arange(0, len(all_mcs.index), 1)

    all_end = timer()
    all_elapsed = round(all_end - all_start, 2)
    llogger.info(" [TIME] All processing took {} sec".format(all_elapsed))

    return all_mcs


def plu_variation(input_files, input_codes, logger=None):
    """ Compute per planning unit (PLU) variation statistics.

    Given a list of input features describing the same planinng units,
    calculate statistics based on defined field names.

    :param input_files: String list of paths to input (vector) features.
    :param input_codes: String list of field names corresponding to each
                        input feature. The statistics will calculated based on
                        these fields.
    :param logger: Logger object.
    :return: GeoPandas DataFrame object.
    """
    # Set up logging
    if not logger:
        logging.basicConfig()
        llogger = logging.getLogger('plu_variation')
        llogger.setLevel(logging.INFO)
    else:
        llogger = logger
    n_features = len(input_files)

    # Create an empty DataFrame to store the rank priority cols
    rank_values = pd.DataFrame({'NUTS_ID': []})

    llogger.info("[1/2] Reading in {} features...".format(n_features))

    for i, feature_file in enumerate(input_files):
        feature_code = input_codes[i]
        prefix = utils.get_iteration_prefix(i+1, n_features)
        llogger.debug("{0} Processing feature {1}".format(prefix,
                                                          feature_file))
        # Read in the feature as GeoPandas dataframe
        feat_data = gpd.read_file(feature_file)
        # Two different field names are used to store the mean rank
        # information: "_mean" for geojson-files and 'Men_rnk' for
        # shapefiles. Figure out which is currently used.
        if '_mean' in feat_data.columns:
            mean_field = '_mean'
        elif 'Men_rnk' in feat_data.columns:
            mean_field = 'Men_rnk'
        else:
            llogger.error("Field '_mean' or 'Men_rnk' not found")
            raise ValueError
        # On first iteration, also get the NUTS_ID column
        if i == 1:
            rank_values['NUTS_ID'] = feat_data['NUTS_ID']
        # Get the rank priority column and place if the store DataFrame
        rank_values[feature_code] = feat_data[mean_field]

    llogger.info("[2/2] Calculating mean and STD...")
    # Read in the first input feature to act as a template.
    output_feature = gpd.read_file(input_files[0])
    # Only take one field: NUTS_ID
    output_feature = output_feature[['geometry', 'NUTS_ID']]
    # Merge with the collected data
    output_feature = output_feature.merge(rank_values, on='NUTS_ID')
    # Calculate mean
    agg_means = output_feature.mean(1)
    # Calculate STD
    agg_stds = output_feature.std(1)
    output_feature['agg_mean'] = agg_means
    output_feature['agg_std'] = agg_stds

    return output_feature
