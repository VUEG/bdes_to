library(raster)
library(sf)
library(tidyverse)


# Helper functions --------------------------------------------------------

get_fz_weights <- function(raster, units) {
  unit_values <- as.data.frame(raster::zonal(raster, units, fun = "sum")) %>% 
    dplyr::rename(ol_sum = sum) %>% 
    dplyr::mutate(weight = ol_sum / sum(ol_sum))
  return(unit_values)
}

flow_zone_units <- raster::raster("data/processed/eurostat/nuts_level0/NUTS_RG_01M_2013_level0.tif")
cli_agro <- raster::raster("data/processed/features/provide/cultural_landscape_index_agro/cultural_landscape_index_agro.tif")
cli_forest <- raster::raster("data/processed/features/provide/cultural_landscape_index_forest/cultural_landscape_index_forest.tif")

cli_agro_weights <- get_fz_weights(cli_agro, flow_zone_units)
cli_forest_weights <- get_fz_weights(cli_forest, flow_zone_units)

readr::write_tsv(cli_agro_weights, "data/WeightsTableCLIagro.txt")
readr::write_tsv(cli_forest_weights, "data/WeightsTableCLIforest.txt")
