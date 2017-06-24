library(rgdal)
library(tidyverse)

check_sizes <- function(path, verbose = FALSE) {
  raster_files <- list.files(path, pattern = "\\.tif$",
                             full.names = TRUE, recursive = TRUE)
  N <- length(raster_files)
  wrong_res <- list(name = c(), rows = c(), cols = c())
  
  pb <- txtProgressBar(min = 1, max = N, style = 3)
  
  for (i in 1:N) {
    
    setTxtProgressBar(pb, i)
    
    raster_file <- raster_files[i]
    
    prefix <- paste0("[", i, "/", N, "] ")
    if (verbose) {
      message(prefix, "Checking: ", raster_file)
    }
    raster_stats <- GDALinfo(raster_file, silent = TRUE)
    raster_size <- c(raster_stats[["rows"]], raster_stats[["columns"]]) 
    if (raster_size[1] != 4410 | raster_size[2] != 4526) {
      warning(prefix, "WARNING: Wrong size for file ", raster_file, " > ", 
              raster_size[1], "x", raster_size[2])
      wrong_res[["name"]] <- c(wrong_res[["name"]], raster_file)
      wrong_res[["rows"]] <- c(wrong_res[["rows"]], raster_size[1])
      wrong_res[["cols"]] <- c(wrong_res[["cols"]], raster_size[2])
    }
  }
  return(dplyr::bind_rows(wrong_res))
}

ws_features <- check_sizes("data/processed/features/", verbose = FALSE)
ws_features_fz <- check_sizes("data/processed/features_flow_zones/", verbose = FALSE)

readr::write_csv(ws_features_fz, "data/size_diff_flow_zones.csv")