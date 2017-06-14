# NOTE: you will need the latest version for this to work
# zonator >= 0.5.3
if (!require("zonator")) {
  devtools::install_github("cbig/zonator", dependencies = TRUE)
}
library(raster)
library(zonator)

priocomp_root <- "~/Dropbox/Projects/VU/OPERAs/SP2/priocomp/"

source(file.path(priocomp_root, "src/00_lib/utils.R"))


# GLOBALS -----------------------------------------------------------------

# Number of features in groups. NOTE: the numbers are hard coded and are
# not updated if the data change.

NAMPHIBIANS <- 83
NBIRDS <- 404
NMAMMALS <- 164
NREPTILES <- 112

NESFEATURES <- 9
NBDFEATURES <- NAMPHIBIANS + NBIRDS + NMAMMALS + NREPTILES
NALLFEATURES <- NESFEATURES + NBDFEATURES

# Groups

GROUPS_ALL <- c(rep(1, NESFEATURES), rep(2, NBDFEATURES))
GROUPNAMES_ALL <- c("1" = "ecosystem_services", "2" = "species")

GROUPS_ES <- c(rep(1, NESFEATURES))
GROUPNAMES_ES <- c("1" = "ecosystem_services")

GROUPS_BD <- c(rep(1, NAMPHIBIANS), rep(2, NBIRDS),
               rep(3, NMAMMALS), rep(4, NREPTILES))
GROUPNAMES_BD <- c("1" = "amphibians", "2" = "birds", "3" = "mammals",
                   "4" = "reptiles")

# Weights

# Create two weight vectors: 1) equal weights for all features (1.0) and
# zero-weight for costs (0.0), and 2) equal aggregate weights.

# 1) Equal feature weights
EQUAL_WEIGHTS_ALL <- c(rep(1, NESFEATURES), rep(1, NBDFEATURES))
EQUAL_WEIGHTS_ES <- c(rep(1, NESFEATURES))
EQUAL_WEIGHTS_BD <- c(rep(1, NBDFEATURES))

# 2) Equal group aggregate weights

# Each group has an equal aggregate weight. To have more intuitive values,
# set the weights of the most numerous group (BD) to 1.0 and have the the
# weights in other groups to be multiples of 1.0.
W_ES <- rep(NBDFEATURES / NESFEATURES, NESFEATURES)
W_BD <- rep(1, NBDFEATURES)

GROUP_WEIGHTS_ALL <- round(c(W_ES, W_BD), 3)

GROUP_WEIGHTS_ES <- EQUAL_WEIGHTS_ES

GROUP_WEIGHTS_BD <- EQUAL_WEIGHTS_BD

# Project variables

VARIANTS <- c("01_caz_all",         "02_abf_all",
              "03_caz_all_wgt",     "04_abf_all_wgt",
              "05_caz_all_wgt_cst", "06_abf_all_wgt_cst",
              "07_caz_es",          "08_abf_es",
              "09_caz_es_cst",      "10_abf_es_cst",
              "11_caz_bd",          "12_abf_bd",
              "13_caz_bd_cst",      "14_abf_bd_cst")

ZSETUP_ROOT <- "zsetup"

PPA_RASTER_FILE <- "data/processed/eurostat/nuts_level2/NUTS_RG_01M_2013_level2.tif"
PPA_CONFIG_FILE <- "ppa_config.txt"

PROJECT_NAME <- "priocomp"

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

rearrange_features <- function(variant) {
  spp_data <- sppdata(variant)
  new_spp_data <- rbind(spp_data[c(1, 3:nrow(spp_data)),], spp_data[2,])
  row.names(new_spp_data) <- 1:nrow(new_spp_data)
  sppdata(variant) <- new_spp_data
  return(variant)
}

setup_costs <- function(variant, group) {
  if (group == "ALL") {
    sppweights(variant) <- GROUP_WEIGHTS_ALL_COST
  } else if (group == "ES") {
    sppweights(variant) <- GROUP_WEIGHTS_ES_COST
  } else if (group == "BD") {
    sppweights(variant) <- GROUP_WEIGHTS_BD_COST
  } else {
    stop("Unknown group: ", group)
  }
  return(variant)
}

setup_groups <- function(variant, group, weights) {
  if (group == "ALL") {
    groups(variant) <- GROUPS_ALL
    groupnames(variant) <- GROUPNAMES_ALL
    if (weights) {
      sppweights(variant) <- GROUP_WEIGHTS_ALL
    } else {
      sppweights(variant) <- EQUAL_WEIGHTS_ALL
    }
  } else if (group == "ES") {
    groups(variant) <- GROUPS_ES
    groupnames(variant) <- GROUPNAMES_ES
    if (weights) {
      sppweights(variant) <- GROUP_WEIGHTS_ES
    } else {
      sppweights(variant) <- EQUAL_WEIGHTS_ES
    }
  } else if (group == "BD") {
    groups(variant) <- GROUPS_BD
    groupnames(variant) <- GROUPNAMES_BD
    if (weights) {
      sppweights(variant) <- GROUP_WEIGHTS_BD
    } else {
      sppweights(variant) <- EQUAL_WEIGHTS_BD
    }
  } else {
    stop("Unknown group: ", group)
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

setup_sppdata <- function(variant, group) {
  variant <- rearrange_features(variant)
  spp_data <- sppdata(variant)
  if (group == "ALL") {
    spp_data <- spp_data
  } else if (group == "ES") {
    spp_data <- rbind(spp_data[1:NESFEATURES,],
                      tail(spp_data, n = NCOSTFEATURES))
  } else if (group == "BD") {
    spp_data <- spp_data[(nrow(spp_data) - NBDFEATURES):nrow(spp_data),]
  } else {
    stop("Unknown group: ", group)
  }
  row.names(spp_data) <- 1:nrow(spp_data)
  sppdata(variant) <- spp_data
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
                         dat_template_file = "analyses/zonation/template.dat",
                         spp_template_dir = "data/processed/features",
                         override_path = "../../../data/processed/features",
                         recursive = TRUE, overwrite = TRUE, debug = TRUE)
priocomp_zproject <- load_zproject(file.path(ZSETUP_ROOT, PROJECT_NAME))

# Set run configuration parameters --------------------------------------------

## 01_caz ---------------------------------------------------------------------

variant1 <- get_variant(priocomp_zproject, 1)
variant1 <- setup_sppdata(variant1, group = "ALL")
variant1 <- setup_groups(variant1, group = "ALL", weights = FALSE)
variant1 <- setup_ppa(variant1)
save_changes(variant1)

## 02_abf ---------------------------------------------------------------------

variant2 <- get_variant(priocomp_zproject, 2)
variant2 <- setup_sppdata(variant2, group = "ALL")
variant2 <- setup_groups(variant2, group = "ALL", weights = FALSE)
# Set removal rule
variant2 <- set_dat_param(variant2, "removal rule", 2)
variant2 <- setup_ppa(variant2)
save_changes(variant2)

## 03_caz_wgt ----------------------------------------------------------------

variant3 <- get_variant(priocomp_zproject, 3)
variant3 <- setup_sppdata(variant3, group = "ALL")
variant3 <- setup_groups(variant3, group = "ALL", weights = TRUE)
variant3 <- setup_ppa(variant3)
save_changes(variant3)

## 04_abf_wgt ----------------------------------------------------------------

variant4 <- get_variant(priocomp_zproject, 4)
variant4 <- setup_sppdata(variant4, group = "ALL")
variant4 <- setup_groups(variant4, group = "ALL", weights = TRUE)
variant4 <- set_dat_param(variant4, "removal rule", 2)
variant4 <- setup_ppa(variant4)
save_changes(variant4)

## 05_caz_wgt_cst ------------------------------------------------------------

variant5 <- get_variant(priocomp_zproject, 5)
variant5 <- setup_sppdata(variant5, group = "ALL")
variant5 <- setup_groups(variant5, group = "ALL", weights = TRUE)
variant5 <- setup_costs(variant5, group = "ALL")
variant5 <- setup_ppa(variant5)
save_changes(variant5)

## 06_abf_wgt_cst -----------------------------------------------------------

variant6 <- get_variant(priocomp_zproject, 6)
variant6 <- setup_sppdata(variant6, group = "ALL")
variant6 <- setup_groups(variant6, group = "ALL", weights = TRUE)
variant6 <- set_dat_param(variant6, "removal rule", 2)
variant6 <- setup_costs(variant6, group = "ALL")
variant6 <- setup_ppa(variant6)
save_changes(variant6)

## 07_caz_es ----------------------------------------------------------------

variant7 <- get_variant(priocomp_zproject, 7)
variant7 <- setup_sppdata(variant7, group = "ES")
variant7 <- setup_groups(variant7, group = "ES", weights = FALSE)
variant7 <- setup_ppa(variant7)
save_changes(variant7)

## 08_abf_es ----------------------------------------------------------------

variant8 <- get_variant(priocomp_zproject, 8)
variant8 <- setup_sppdata(variant8, group = "ES")
variant8 <- setup_groups(variant8, group = "ES", weights = FALSE)
variant8 <- set_dat_param(variant8, "removal rule", 2)
variant8 <- setup_ppa(variant8)
save_changes(variant8)

## 09_caz_es_cst -----------------------------------------------------------

variant9 <- get_variant(priocomp_zproject, 9)
variant9 <- setup_sppdata(variant9, group = "ES")
variant9 <- setup_groups(variant9, group = "ES", weights = FALSE)
variant9 <- setup_costs(variant9, group = "ES")
variant9 <- setup_ppa(variant9)
save_changes(variant9)

## 10_abf_es_cst -----------------------------------------------------------

variant10 <- get_variant(priocomp_zproject, 10)
variant10 <- setup_sppdata(variant10, group = "ES")
variant10 <- setup_groups(variant10, group = "ES", weights = FALSE)
variant10 <- set_dat_param(variant10, "removal rule", 2)
variant10 <- setup_costs(variant10, group = "ES")
variant10 <- setup_ppa(variant10)
save_changes(variant10)

## 11_caz_bd ----------------------------------------------------------------

variant11 <- get_variant(priocomp_zproject, 11)
variant11 <- setup_sppdata(variant11, group = "BD")
variant11 <- setup_groups(variant11, group = "BD", weights = FALSE)
variant11 <- setup_ppa(variant11)
save_changes(variant11)

## 12_abf_bd ----------------------------------------------------------------

variant12 <- get_variant(priocomp_zproject, 12)
variant12 <- setup_sppdata(variant12, group = "BD")
variant12 <- setup_groups(variant12, group = "BD", weights = FALSE)
variant12 <- set_dat_param(variant12, "removal rule", 2)
variant12 <- setup_ppa(variant12)
save_changes(variant12)

## 13_caz_bd_cst -----------------------------------------------------------

variant13 <- get_variant(priocomp_zproject, 13)
variant13 <- setup_sppdata(variant13, group = "BD")
variant13 <- setup_groups(variant13, group = "BD", weights = FALSE)
variant13 <- setup_costs(variant13, group = "BD")
variant13 <- setup_ppa(variant13)
save_changes(variant13)

## 14_abf_bd_cst -----------------------------------------------------------

variant14 <- get_variant(priocomp_zproject, 14)
variant14 <- setup_sppdata(variant14, group = "BD")
variant14 <- setup_groups(variant14, group = "BD", weights = FALSE)
variant14 <- set_dat_param(variant14, "removal rule", 2)
variant14 <- setup_costs(variant14, group = "BD")
variant14 <- setup_ppa(variant14)
save_changes(variant14)

# PRE-LOADING

folder_prefix <- paste0(ZSETUP_ROOT, "/", PROJECT_NAME, "/")

## 15_load_es_all ----------------------------------------------------------
#  -> setup from 04_abf_wgt, ranking from (expanded) 08_abf_es

load_rank_raster <- file.path(gsub(folder_prefix,"", variant8@results@root),
                              "08_abf_es.rank_expanded.compressed.tif")
create_load_variant(name = "15_load_es_all", setup_variant = variant4,
                    load_raster = load_rank_raster)

## 16_load_bd_all ----------------------------------------------------------
#  -> setup from 04_abf_wgt, ranking from (expanded) 12_abf_bd

load_rank_raster <- file.path(gsub(folder_prefix,"", variant12@results@root),
                              "12_abf_bd.rank_expanded.compressed.tif")
create_load_variant(name = "16_load_bd_all", setup_variant = variant4,
                    load_raster = load_rank_raster)

## 17_load_es_all_cst ------------------------------------------------------
#  -> setup from 06_abf_wgt_cst, ranking from (expanded) 10_abf_es_cst

load_rank_raster <- file.path(gsub(folder_prefix,"", variant10@results@root),
                              "10_abf_es_cst.rank_expanded.compressed.tif")
create_load_variant(name = "17_load_es_all_cst", setup_variant = variant6,
                    load_raster = load_rank_raster)

## 18_load_bd_all_cst ------------------------------------------------------
#  -> setup from 06_abf_wgt_cst, ranking from (expanded) 14_abf_bd_cst

load_rank_raster <- "14_abf_bd_cst.rank_expanded.compressed.tif"
create_load_variant(name = "18_load_bd_all_cst", setup_variant = variant6,
                    load_raster = file.path(variant14@results@root,
                                            load_rank_raster))

## 19_load_es_bd -----------------------------------------------------------
#  -> setup from 12_abf_bd, ranking from (matched) 08_abf_es

load_rank_raster <- file.path(gsub(folder_prefix,"", variant8@results@root),
                              "08_abf_es.rank_bd_matched.compressed.tif")
create_load_variant(name = "19_load_es_bd", setup_variant = variant12,
                    load_raster = load_rank_raster)

## 20_load_bd_es -----------------------------------------------------------
#  -> setup from 08_abf_es, ranking from (matched) 12_abf_bd

load_rank_raster <- file.path(gsub(folder_prefix,"", variant12@results@root),
                              "12_abf_bd.rank_es_matched.compressed.tif")
create_load_variant(name = "20_load_bd_es", setup_variant = variant8,
                    load_raster = load_rank_raster)

## 21_load_es_bd_cst -------------------------------------------------------
#  -> setup from 14_abf_bd_cst, ranking from (matched) 10_abf_es_cst

load_rank_raster <- file.path(gsub(folder_prefix,"", variant10@results@root),
                              "10_abf_es_cst.rank_bd_matched.compressed.tif")
create_load_variant(name = "21_load_es_bd_cst", setup_variant = variant14,
                    load_raster = load_rank_raster)

## 22_load_bd_es_cst -------------------------------------------------------
#  -> setup from 10_abf_es_cst, ranking from (matched) 14_abf_bd_cst

load_rank_raster <- file.path(gsub(folder_prefix,"", variant14@results@root),
                              "14_abf_bd_cst.rank_es_matched.compressed.tif")
create_load_variant(name = "22_load_bd_es_cst", setup_variant = variant10,
                    load_raster = load_rank_raster)

## 23_load_rwr_all ---------------------------------------------------------
#  -> setup from 04_abf_wgt, ranking from (expanded) rwr_all_weights

load_rank_raster <- "../../RWR/rwr_all_weights_expanded.tif"
create_load_variant(name = "23_load_rwr_all", setup_variant = variant4,
                    load_raster = load_rank_raster)

## 24_load_ilp_all ---------------------------------------------------------
#  -> setup from 04_abf_wgt, ranking from (expanded) ilp_all_weights

load_rank_raster <- "../../ILP/ilp_all_weights_expanded.tif"
create_load_variant(name = "24_load_ilp_all", setup_variant = variant4,
                    load_raster = load_rank_raster)

## 25_load_rwr_all_cst -----------------------------------------------------
#  -> setup from 06_abf_wgt_cst, ranking from (expanded) rwr_all_weights_cost

load_rank_raster <- "../../RWR/rwr_all_weights_costs_expanded.tif"
create_load_variant(name = "25_load_rwr_all_cst", setup_variant = variant6,
                    load_raster = load_rank_raster)

## 26_load_ilp_all_cst -----------------------------------------------------
#  -> setup from 06_abf_wgt_cst, ranking from (expanded) ilp_all_weights_cost

load_rank_raster <- "../../ILP/ilp_all_weights_costs_expanded.tif"
create_load_variant(name = "26_load_ilp_all_cst", setup_variant = variant6,
                    load_raster = load_rank_raster)
