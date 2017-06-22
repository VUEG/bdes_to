library(raster)
library(tidyverse)

# Helper functions --------------------------------------------------------

get_fz_weights <- function(raster, units) {
  unit_values <- as.data.frame(raster::zonal(raster, units, fun = "sum")) %>% 
    dplyr::rename(ol_sum = sum) %>% 
    dplyr::mutate(weight = ol_sum / sum(ol_sum))
  return(unit_values)
}

flow_zone_units <- raster::raster("data/processed/eurostat/nuts_level0/NUTS_RG_01M_2013_level0.tif")
# Make a global mask
flow_zone_units_global <- flow_zone_units > 0

# Regional
cli_agro <- raster::raster("data/processed/features/provide/cultural_landscape_index_agro/cultural_landscape_index_agro.tif")
cli_forest <- raster::raster("data/processed/features/provide/cultural_landscape_index_forest/cultural_landscape_index_forest.tif")

cli_agro_weights <- get_fz_weights(cli_agro, flow_zone_units)
cli_forest_weights <- get_fz_weights(cli_forest, flow_zone_units)

# Global
carbon <- raster::raster("data/processed/features/provide/carbon_sequestration/carbon_sequestration.tif")
tourism <- raster::raster("data/processed/features/provide/nature_tourism/nature_tourism.tif")

carbon_weights <- get_fz_weights(carbon, flow_zone_units_global)
tourism_weights <- get_fz_weights(tourism, flow_zone_units_global)


# Write data --------------------------------------------------------------

readr::write_tsv(cli_agro_weights, "data/WeightsTableCLIagro.txt")
readr::write_tsv(cli_forest_weights, "data/WeightsTableCLIforest.txt")

readr::write_tsv(carbon_weights, "data/WeightsTableCarbon.txt")
readr::write_tsv(tourism_weights, "data/WeightsTableNtourism.txt")
