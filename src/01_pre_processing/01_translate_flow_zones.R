library(gdalUtils)
library(purrr)
library(spatial.tools)

# Helper functions --------------------------------------------------------

translate_dir <- function(src_dir, dst_dir, cpus = 4) {
  
  message("Initiating a parallel PSOCK cluster with ", cpus, " cpus")
  spatial.tools::sfQuickInit(cpus = cpus) 
  batch_gdal_translate(infiles = src_dir, outdir = dst_dir, recursive = TRUE,
                       pattern = ".tif$", outsuffix = ".tif", 
                       a_srs = "EPSG:3035", co = c("compress=DEFLATE"), 
                       verbose = TRUE)
  sfQuickStop()
}

process_zip <- function(src_zip, dst_zip, keep_translated = FALSE) {
  
  temp_dir <- dirname(src_zip)
  
  temp_dir_translated <- paste0(gsub("\\.zip", "", src_zip), "_translated")
  if (!dir.exists(temp_dir_translated)) {
    dir.create(temp_dir_translated)
  }
  
  message("Unzipping original files...")
  unzip(src_zip, exdir = temp_dir)
  message("Batch translating original files...")
  translate_dir(temp_dir, temp_dir_translated)
  unlink(dirname(temp_dir), force = TRUE)
  message("Zipping translated files...")
  zip(zipfile = dst_zip, files = list.files(temp_dir_translated, 
                                            full.names = TRUE),
      extras = c("-q"))
  if (!keep_translated) {
    unlink(temp_dir_translated, force = TRUE)
  }
  
  message("Translated files are found compressed at: ", dst_zip)
  return(invisible(TRUE))
}


process_zip("data/transfer/willem verhagen - airquality.zip",
            "data/transfer/air_quality_flow_zones", keep_translated = TRUE)
process_zip("data/transfer/willem verhagen - floodregulation.zip",
            "data/transfer/floodregulation_flow_zones.zip", keep_translated = TRUE)

