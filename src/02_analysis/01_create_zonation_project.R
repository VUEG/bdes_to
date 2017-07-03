# NOTE: you will need the latest version for this to work
# zonator >= 0.5.3
if (!require("zonator")) {
  devtools::install_github("cbig/zonator", dependencies = TRUE)
}
library(raster)
library(tidyverse)
library(zonator)

priocomp_root <- "~/Dropbox/Projects/VU/OPERAs/SP2/priocomp/"

source(file.path(priocomp_root, "src/00_lib/utils.R"))


# GLOBALS -----------------------------------------------------------------

# Number of features in groups. NOTE: the numbers are hard coded and are
# not updated if the data change.

count_files <- function(x) {
  n <- 0
  for (path in x) {
    n <- n + length(list.files(path, pattern = "\\.tif$", recursive = TRUE))
  }
  return(n)
}

NAMPHIBIANS <- count_files("data/processed/features/udr/european_tetrapods/amphibians/")
NBIRDS <- count_files("data/processed/features/udr/european_tetrapods/birds/")
NMAMMALS <- count_files("data/processed/features/udr/european_tetrapods/mammals/")
NREPTILES <- count_files("data/processed/features/udr/european_tetrapods/reptiles/")
NBIO <- NAMPHIBIANS + NBIRDS + NMAMMALS + NREPTILES

# Capacity
NESC <- count_files(c("data/processed/features/provide/pollination_flows",
                      "data/processed/features/jrc/air_quality",
                      "data/processed/features/provide/cultural_landscape_index_agro",
                      "data/processed/features/provide/cultural_landscape_index_forest",
                      "data/processed/features/provide/floodregulation",
                      "data/processed/features/provide/carbon_sequestration/",
                      "data/processed/features/provide/nature_tourism"))
# Flowzones
# Local
NESF_LOC <- count_files(c("data/processed/features_flow_zones/provide/pollination_flow_flow_zones/",
                          "data/processed/features_flow_zones/jrc/air_quality_flow_zones/"))
# Regional
NESF_REG <- count_files(c("data/processed/features_flow_zones/provide/cultural_landscape_index_agro_flow_zones/",
                          "data/processed/features_flow_zones/provide/cultural_landscape_index_forest_flow_zones/",
                          "data/processed/features_flow_zones/provide/floodregulation_flow_zones/"))
# Global
NESF_GLO <- count_files(c("data/processed/features/provide/carbon_sequestration/",
                          "data/processed/features/provide/nature_tourism/"))

# All
NESF <- NESF_LOC + NESF_REG + NESF_GLO

NALL <- NBIO + NESC + NESF

# Project variables

VARIANTS <- c("01_abf_bio", 
              "02_abf_car", 
              "03_abf_esc",
              "04_abf_esf", 
              "05_abf_bio_car", 
              "06_abf_bio_esc",
              "07_abf_bio_esf")

ZSETUP_ROOT <- "zsetup"

PPA_RASTER_FILE <- "../../data/processed/eurostat/nuts_level0/NUTS_RG_01M_2013_level0.tif"
PPA_CONFIG_FILE <- "ppa_config.txt"

PROJECT_NAME <- "bdes_to"

# Flowzone-specifc weights
fz_weights <- list()
# Local
fz_weights[["pollination"]] <- readr::read_tsv("data/WeightsTablePollination.txt") %>% 
  dplyr::select(FID, SUM, weight) %>% 
  dplyr::rename(id = FID, sum = SUM) %>% 
  dplyr::mutate(name = paste0("pollFZ", id), group = "local")
fz_weights[["airquality"]] <- readr::read_tsv("data/WeightsTableAirq.txt") %>% 
  dplyr::select(FID, SUM, weightAirq) %>% 
  dplyr::rename(id = FID, sum = SUM, weight = weightAirq) %>% 
  dplyr::mutate(name = paste0("airqFZ", id), group = "local")
# Regional
fz_weights[["cli_agro"]] <- readr::read_tsv("data/WeightsTableCLIagro.txt") %>% 
  dplyr::select(zone, ol_sum, weight) %>% 
  dplyr::rename(id = zone, sum = ol_sum) %>% 
  dplyr::mutate(name = paste0("cultural_landscape_index_agro_", id), group = "regional")
fz_weights[["cli_forest"]] <- readr::read_tsv("data/WeightsTableCLIforest.txt") %>% 
  dplyr::select(zone, ol_sum, weight) %>% 
  dplyr::rename(id = zone, sum = ol_sum) %>% 
  dplyr::mutate(name = paste0("cultural_landscape_index_forest_", id), group = "regional")
fz_weights[["floodregulation"]] <- readr::read_tsv("data/WeightsTableFloodReg.txt") %>% 
  dplyr::select(FID, SUM, weightFlood) %>% 
  dplyr::rename(id = FID, sum = SUM, weight = weightFlood) %>% 
  dplyr::mutate(name = paste0("floodFZ", id), group = "regional")
# Global
fz_weights[["carbon"]] <- readr::read_tsv("data/WeightsTableCarbon.txt") %>% 
  dplyr::select(zone, ol_sum, weight) %>% 
  dplyr::rename(id = zone, sum = ol_sum) %>% 
  dplyr::mutate(name = "carbon_sequestration", group = "global")
fz_weights[["nature_tourism"]] <- readr::read_tsv("data/WeightsTableNtourism.txt") %>% 
  dplyr::select(zone, ol_sum, weight) %>% 
  dplyr::rename(id = zone, sum = ol_sum) %>% 
  dplyr::mutate(name = "nature_tourism", group = "global")
# Bind all
fz_weights <- dplyr::bind_rows(fz_weights)
# Balance the weights so that:
# 1. Each group (local, regional and global) has the same aggregate weight

group_aggs <- fz_weights %>% 
  group_by(group) %>% 
  summarise(
    agg = sum(weight)
  )

fz_weights <- fz_weights %>% 
  dplyr::left_join(group_aggs, by = c("group" = "group")) %>% 
  dplyr::mutate(weight = weight / agg) %>% 
  dplyr::select(-group, -agg)

# Helper functions --------------------------------------------------------

create_sh_file <- function(x) {
  if (class(x) == "Zvariant") {
    bat_file <- x@bat.file
  } else {
    bat_file <- x
  }

  sh_file <- gsub("\\.bat", "\\.sh", bat_file)

  cmd_lines <- readLines(bat_file)
  new_cmd_lines <- c("#!/bin/sh")

  for (line in cmd_lines) {
    line <- gsub("call ", "", line)
    line <- gsub("\\.exe", "", line)
    new_cmd_lines <- c(new_cmd_lines, line)
  }

  file_con <- file(sh_file)
  writeLines(new_cmd_lines, file_con)
  close(file_con)
  Sys.chmod(sh_file)
  return(invisible(TRUE))
}


create_load_variant <- function(name, setup_variant, load_raster) {
  from_name <- setup_variant@name
  to_name <- name
  # Copy and rename the setup variant
  from_dir <- file.path(ZSETUP_ROOT, PROJECT_NAME, from_name)
  to_dir <- file.path(ZSETUP_ROOT, PROJECT_NAME, to_name)
  dir.create(to_dir)
  from_files <- list.files(from_dir, full.names = TRUE,
                           recursive = TRUE, include.dirs = TRUE)
  invisible(file.copy(from_files, to_dir, recursive = TRUE))
  # Rename subcomponents
  to_files <- list.files(to_dir, full.names = TRUE,
                         recursive = TRUE, include.dirs = TRUE)
  for (from_item in to_files) {
    to_item <- gsub(from_name, to_name, from_item)
    file.rename(from_item, to_item)
  }
  # List renamed files
  to_files <- list.files(to_dir, full.names = TRUE,
                         recursive = TRUE, include.dirs = TRUE)
  
  # Rename the groups file definition in dat file
  dat_file <- to_files[grepl("\\.dat$", to_files)]
  dat_content <- readLines(dat_file, -1)
  grp_file_def <- dat_content[grepl("^groups file", dat_content)]
  dat_content[grepl("^groups file", dat_content)] <- gsub(from_name, to_name, grp_file_def)
  writeLines(dat_content, dat_file)
  
  # Copy and modify the bat-file
  from_bat_file <- setup_variant@bat.file
  to_bat_file <- gsub(from_name, to_name, from_bat_file)
  invisible(file.copy(from_bat_file, to_bat_file))
  bat_content <- readLines(to_bat_file, -1)
  bat_content <- gsub(from_name, to_name, bat_content)
  # Replace new solution call with the loading command
  bat_content <- gsub("-r", paste0("-l", load_raster), bat_content)
  writeLines(bat_content, to_bat_file)
  # Create a sh-file
  create_sh_file(to_bat_file)
  
  return(invisible(TRUE))
}

process_esf_sppdata <- function(spp_data, weights) {
  spp_data <- dplyr::left_join(spp_data, weights, 
                               by = c("name" = "name"))
  
  if (any(is.na(spp_data$weight.y))) {
    missing_weights <- spp_data %>% 
      dplyr::filter(is.na(weight.y)) %>% 
      dplyr::pull(name)
    warning("Following flow zones have no additional weights: ", 
            paste(missing_weights, collapse = ", "), ". Setting weight to zero.")
    spp_data[is.na(spp_data$weight.y), ]$weight.y <- 0
  }
  
  spp_data <- spp_data %>% 
    dplyr::mutate(weight = weight.y) %>% 
    dplyr::select(weight, dplyr::everything(), 
                  -weight.x, -weight.y, -sum, -id)
  
  return(spp_data)
}

setup_groups <- function(variant, group, multiplier=1) {
  
  groups_bd <- c(rep(1, NAMPHIBIANS), rep(2, NBIRDS),
                 rep(3, NMAMMALS), rep(4, NREPTILES))
  groupnames_bd <- c("1" = "amphibians", "2" = "birds", "3" = "mammals",
                     "4" = "reptiles")
  
  if (group == "bio") {
    groups(variant) <- groups_bd
    groupnames(variant) <- groupnames_bd
    sppweights(variant) <- c(rep(1, NBIO))
  } else if (group == "esc") {
    groups(variant) <- c(rep(1, 2), rep(2, 3), rep(3, 2))
    groupnames(variant) <- c("1" = "esc_loc", "2" = "esc_reg", "3" = "esc_glo")
    sppweights(variant) <- c(rep(1 / 2, 2), rep(1 / 3, 3), rep(1 / 2, 2))
  } else if (group == "esf") {
    sppdata(variant) <- process_esf_sppdata(zonator::sppdata(variant), 
                                            fz_weights)
    groups(variant) <- c(rep(1, NESF_LOC),
                         rep(2, NESF_REG),
                         rep(3, NESF_GLO))
    groupnames(variant) <- c("1" = "esf_loc", "2" = "esf_reg", "3" = "esf_glo")
  } else if (group == "bio_car") {
    groups(variant) <- c(rep(1, NBIO), 2)
    groupnames(variant) <- c("1" = "bio", "2" = "car")
    # Carbon gets the same weight as all BD features together
    sppweights(variant) <- c(rep(1, NBIO), NBIO)
  } else if (group == "bio_esc") {
    groups(variant) <- c(rep(1, NBIO), rep(2, NESC))
    groupnames(variant) <- c("1" = "bio", "2" = "esc")
    # Use the same weight dividsion for esc as before
    sppweights(variant) <- c(rep(1, NBIO), 
                             c(rep(1 / 3 / 2, 2), rep(1 / 3 / 3, 3), rep(1 / 3 / 2, 2)) * NBIO)
  } else if (group == "bio_esf") {
    # Get only ESF data
    spp_data <- zonator::sppdata(variant)
    spp_data_esf <- spp_data[(NBIO + 1):nrow(spp_data),]
    spp_data_esf <- process_esf_sppdata(spp_data_esf, fz_weights)
    # ESF are weighted internally as in "esf". These weights add up
    # to 9.0, so divide fz_weights
    spp_data_esf$weight <- spp_data_esf$weight / 3
    
    sppweights(variant) <- c(rep((1.0 / NBIO), NBIO), spp_data_esf$weight)
    groups(variant) <- c(rep(1, NBIO), rep(2, NESF))
    groupnames(variant) <- c("1" = "bio", "2" = "esf")
  } else {
    stop("Unknown group: ", group)
  }
  
  if (!is.null(multiplier)) {
    sppweights(variant) <- sppweights(variant) * multiplier 
  }
  
  # Set groups use and groups file
  variant <- set_dat_param(variant, "use groups", 1)
  # Note that groups file location is always relative to the bat file
  groups_file <- file.path(variant@name, paste0(variant@name, "_groups.txt"))
  variant <- set_dat_param(variant, "groups file", groups_file)
  return(variant)
}

setup_ppa <- function(variant) {
  # Set post-processing (LSM). First, let's create the file itself (zonator
  # can't handle this yet). The file needs to be created only once per taxon
  # since all the variants can use the same file.
  if (!file.exists(PPA_CONFIG_FILE)) {
    ppa_file_name <- file.path(ZSETUP_ROOT, PROJECT_NAME, PPA_CONFIG_FILE)
    ppa_cmd_string <- paste(c("LSM", PPA_RASTER_FILE, 0, -1, 0), collapse = " ")
    write(ppa_cmd_string, ppa_file_name)
  }

  # Need to define ppa_config.txt relative to the bat-file (same dir)
  variant <- set_dat_param(variant, "post-processing list file",
                           PPA_CONFIG_FILE)
  return(variant)
}

setup_sppdata <- function(variant, prefix, ...) {
  
  spp_file <- variant@call.params$spp.file
  # Delete the existing (dummy) spp-file 
  file.remove(spp_file)
  # Create a new spp-file based on the feature dir(s)
  zonator::create_spp(filename = spp_file, ...)
  # Read in the spp data and manually create the name column
  spp_data <- zonator::read_spp(spp_file) 
  if (!is.null(prefix)) {
    # Manually prefix the file paths
    spp_data$filepath <- paste0(prefix, spp_data$filepath)
  }
  
  spp_data$name <- gsub(".tif", "", basename(spp_data$filepath))
  zonator::sppdata(variant) <- spp_data
  return(variant)
}

save_changes <- function(variant) {
  # Save variant
  save_zvariant(variant, dir = file.path(ZSETUP_ROOT, PROJECT_NAME),
                overwrite = TRUE, debug_msg = FALSE)

  # Create a sh file for Linux
  create_sh_file(variant)
  return(invisible(TRUE))
}

# Generate variants for all taxa ------------------------------------------

zonator::create_zproject(name = PROJECT_NAME, dir = ZSETUP_ROOT, variants = VARIANTS,
                         dat_template_file = "zsetup/template.dat",
                         spp_template_file = "zsetup/template.spp",
                         overwrite = TRUE, debug = TRUE)
priocomp_zproject <- load_zproject(file.path(ZSETUP_ROOT, PROJECT_NAME))

# Set run configuration parameters --------------------------------------------


## 01_abf_bio -----------------------------------------------------------------

variant1 <- get_variant(priocomp_zproject, 1)
variant1 <- setup_sppdata(variant1, spp_file_dir = "data/processed/features/udr", 
                          recursive = TRUE, prefix = "../../")
variant1 <- setup_groups(variant1, group = "bio")
variant1 <- set_dat_param(variant1, "removal rule", 2)
variant1 <- setup_ppa(variant1)
save_changes(variant1)

## 02_abf_car -----------------------------------------------------------------

variant2 <- get_variant(priocomp_zproject, 2)
variant2 <- setup_sppdata(variant2, spp_file_dir = "data/processed/features/provide/carbon_sequestration", 
                          recursive = FALSE, prefix = "../../")
# Set removal rule
variant2 <- set_dat_param(variant2, "removal rule", 2)
variant2 <- setup_ppa(variant2)
save_changes(variant2)

## 03_abf_esc ----------------------------------------------------------------

variant3 <- get_variant(priocomp_zproject, 3)
variant3 <- setup_sppdata(variant3, spp_file_dir = c("data/processed/features/provide/pollination_flows",
                                                     "data/processed/features/jrc/air_quality",
                                                     "data/processed/features/provide/cultural_landscape_index_agro",
                                                     "data/processed/features/provide/cultural_landscape_index_forest",
                                                     "data/processed/features/provide/floodregulation",
                                                     "data/processed/features/provide/carbon_sequestration/",
                                                     "data/processed/features/provide/nature_tourism"), 
                          recursive = TRUE, prefix = "../../")
variant3 <- setup_groups(variant3, group = "esc")
variant3 <- set_dat_param(variant3, "removal rule", 2)
variant3 <- setup_ppa(variant3)
save_changes(variant3)

## 04_abf_esf ----------------------------------------------------------------

variant4 <- get_variant(priocomp_zproject, 4)
variant4 <- setup_sppdata(variant4, 
                          spp_file_dir = c("data/processed/features_flow_zones/provide/pollination_flow_flow_zones",
                                           "data/processed/features_flow_zones/jrc/air_quality_flow_zones",
                                           "data/processed/features_flow_zones/provide/cultural_landscape_index_agro_flow_zones",
                                           "data/processed/features_flow_zones/provide/cultural_landscape_index_forest_flow_zones",
                                           "data/processed/features_flow_zones/provide/floodregulation_flow_zones",
                                           "data/processed/features/provide/carbon_sequestration",
                                           "data/processed/features/provide/nature_tourism"),
                          recursive = TRUE, prefix = "../../")
variant4 <- setup_groups(variant4, group = "esf", multiplier = 10000)
variant4 <- set_dat_param(variant4, "removal rule", 2)
variant4 <- setup_ppa(variant4)
save_changes(variant4)

## 05_abf_bio_car ------------------------------------------------------------

variant5 <- get_variant(priocomp_zproject, 5)
variant5 <- setup_sppdata(variant5, spp_file_dir = c("data/processed/features/udr/",
                                                     "data/processed/features/provide/carbon_sequestration/"), 
                          recursive = TRUE, prefix = "../../")
variant5 <- setup_groups(variant5, group = "bio_car")
variant5 <- setup_ppa(variant5)
save_changes(variant5)

## 06_abf_bio_esc -----------------------------------------------------------

variant6 <- get_variant(priocomp_zproject, 6)
variant6 <- setup_sppdata(variant6, spp_file_dir = c("data/processed/features/udr/",
                                                     "data/processed/features/provide/pollination_flows",
                                                     "data/processed/features/jrc/air_quality",
                                                     "data/processed/features/provide/cultural_landscape_index_agro",
                                                     "data/processed/features/provide/cultural_landscape_index_forest",
                                                     "data/processed/features/provide/floodregulation",
                                                     "data/processed/features/provide/carbon_sequestration/",
                                                     "data/processed/features/provide/nature_tourism"), 
                          recursive = TRUE, prefix = "../../")
variant6 <- setup_groups(variant6, group = "bio_esc")
variant6 <- set_dat_param(variant6, "removal rule", 2)
variant6 <- setup_ppa(variant6)
save_changes(variant6)

## 07_abf_bio_esf -----------------------------------------------------------

variant7 <- get_variant(priocomp_zproject, 7)
variant7 <- setup_sppdata(variant7, spp_file_dir = c("data/processed/features/udr/",
                                                     "data/processed/features_flow_zones/provide/pollination_flow_flow_zones",
                                                     "data/processed/features_flow_zones/jrc/air_quality_flow_zones",
                                                     "data/processed/features_flow_zones/provide/cultural_landscape_index_agro_flow_zones",
                                                     "data/processed/features_flow_zones/provide/cultural_landscape_index_forest_flow_zones",
                                                     "data/processed/features_flow_zones/provide/floodregulation_flow_zones",
                                                     "data/processed/features/provide/carbon_sequestration/",
                                                     "data/processed/features/provide/nature_tourism"),
                          recursive = TRUE, prefix = "../../")
variant7 <- setup_groups(variant7, group = "bio_esf",  multiplier = 10000)
variant7 <- setup_ppa(variant7)
save_changes(variant7)

# PRE-LOADING

folder_prefix <- paste0(ZSETUP_ROOT, "/", PROJECT_NAME, "/")

## 08_prl_car_bio -----------------------------------------------------------

load_rank_raster <- file.path(gsub(folder_prefix,"", variant2@results@root),
                              "02_abf_car.rank_matched.compressed.tif")
create_load_variant(name = "08_prl_car_bio", setup_variant = variant1,
                    load_raster = load_rank_raster)

## 09_prl_esc_bio -----------------------------------------------------------

load_rank_raster <- file.path(gsub(folder_prefix,"", variant3@results@root),
                              "03_abf_esc.rank_matched.compressed.tif")
create_load_variant(name = "09_prl_esc_bio", setup_variant = variant1,
                    load_raster = load_rank_raster)

## 10_prl_esf_bio -----------------------------------------------------------

load_rank_raster <- file.path(gsub(folder_prefix,"", variant4@results@root),
                              "04_abf_esf.rank_matched.compressed.tif")
create_load_variant(name = "10_prl_esf_bio", setup_variant = variant1,
                    load_raster = load_rank_raster)

## 11_prl_biocar_bio -----------------------------------------------------------

load_rank_raster <- file.path(gsub(folder_prefix,"", variant5@results@root),
                              "05_abf_bio_car.rank_matched.compressed.tif")
create_load_variant(name = "11_prl_biocar_bio", setup_variant = variant1,
                    load_raster = load_rank_raster)

## 12_prl_bioesc_bio -----------------------------------------------------------

load_rank_raster <- file.path(gsub(folder_prefix,"", variant6@results@root),
                              "06_abf_bio_esc.rank_matched.compressed.tif")
create_load_variant(name = "11_prl_bioesc_bio", setup_variant = variant1,
                    load_raster = load_rank_raster)

## 13_prl_bioesf_bio -----------------------------------------------------------

load_rank_raster <- file.path(gsub(folder_prefix,"", variant7@results@root),
                              "07_abf_bio_esf.rank_matched.compressed.tif")
create_load_variant(name = "13_prl_bioesf_bio", setup_variant = variant1,
                    load_raster = load_rank_raster)
