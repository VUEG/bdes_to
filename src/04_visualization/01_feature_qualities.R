library(dplyr)
library(gganimate)
library(ggplot2)
library(hrbrthemes)
library(purrr)
library(RColorBrewer)
library(readr)
library(tidyr)
library(zonator)
library(viridis)

zjapan_root <- "~/Dropbox/project.J-PriPA/japan-zsetup"

source(file.path(zjapan_root, "R/00_lib/utils.R"))

# Helper functions --------------------------------------------------------

get_feature_ranges <- function() {
  feature_ranges <- readr::read_csv("data/feature_ranges.csv") %>%
    dplyr::slice(11:n()) %>% 
    dplyr::select(feature_long = feature, dplyr::everything()) %>%
    dplyr::mutate(feature = gsub("\\.tif$", "", basename(feature_long))) %>%
    dplyr::select(feature, dplyr::everything(), -feature_long)
  return(feature_ranges)
}

get_feature_rl <- function() {
  feature_rl <- readr::read_csv("data/spp_rl_statuses.csv") %>%
    dplyr::mutate(feature = tolower(gsub("\\s", "_", species))) %>%
    dplyr::mutate(status = gsub("LR/nt", "NT", status)) %>%
    dplyr::mutate(status = factor(status, levels = c("DD", "LC", "NT", "VU", "EN", "CR")))
  return(feature_rl)
}

get_feature_performance <- function(src_zproject, src_variant_id, 
                                dst_variant_name, top, groups = NULL) {
  feature_perf <- zonator::get_variant(src_zproject, src_variant_id) %>%
    # Get results associated with the variant
    zonator::results() %>%
    # Get the performance data from results for the top fraction
    zonator::performance(pr.lost = top) %>%
    # Get rid of the original pr_lost
    dplyr::select(-pr_lost) %>%
    # Make feature / proportion remaining long
    tidyr::gather(feature, pr_rem) %>% 
    # Rename variant and add top fraction
    dplyr::mutate(variant = dst_variant_name,
                  fraction = paste0((1.0 - top) * 100, "%")) %>% 
    # Join together with aux data
    dplyr::left_join(get_feature_ranges()) %>%
    dplyr::left_join(get_feature_rl()) %>%
    # Calculate more stats
    dplyr::mutate(log_count = log(count),
                  log_mean_ol = log(mean_ol),
                  count_rank = row_number(count),
                  mean_ol_rank = row_number(-mean_ol))
  if (is.null(groups)) {
    # If no groups are provided, use 1 for everything
    groups <- 1
  }
  feature_perf$group <- groups
  return(feature_perf)
}

# Load variants and configure groups --------------------------------------

# Load the project, creates japan_zproject. WARNING: loaded object is cached
# using memoise-package. If results have change, don't load the cached version.
# Also if the cache needs to updated, you will have to do this manually.
# > key <- list("zsetup/bdes_to")
# > saveCache(zproject, key = key)
zproject <- .load_zproject("zsetup/bdes_to", cache = TRUE, debug = TRUE)

new_groups <- c(rep("Amphibians", 83), rep("Birds", 404), rep("Mammals", 164),
                rep("Reptiles", 112))

# Process variants --------------------------------------------------------

# Variants are (sorted in logical order):
# 01_abf_bio        - Baseline (BD only)
#
# 11_prl_biocar_bio - Priority ranking from carbon+BD, performance BD
# 08_prl_car_bio    - Priority ranking from carbon, performance BD
#
# 12_prl_bioesc_bio - Priority ranking from ESs capacity+BD, performance BD
# 09_prl_esc_bio    - Priority ranking from ESs capacity, performance BD
#
# 13_prl_bioesf_bio - Priority ranking from ESs flowzones+BD, performance BD
# 10_prl_esf_bio    - Priority ranking from ESs flowzones, performance BD

# Get performance for top 10% and Drop first column (pr_lost)

top_fraction <- 0.90
top_fractions <- seq(0.9, 0.1, -0.05)

all_feature_data <- list()

for (top_fraction in top_fractions) {
  variant_ids <- c(11, 8, 12, 9, 13, 10, 1)
  variant_names <- c("biocar", "car", "bioesc", "esc", "bioesf", "esf", "bio")
  
  feature_data <- purrr::map2(variant_ids, variant_names, 
                              get_feature_performance, src_zproject = zproject, 
                              top = top_fraction, groups = new_groups) %>% 
    dplyr::bind_rows()
  
  feature_data$variant <- factor(feature_data$variant, levels = variant_names)
  all_feature_data[[as.character(top_fraction)]] <- feature_data
}

feature_data <- dplyr::bind_rows(all_feature_data)

# Count differences between ranks between the baseline (bio) and everything 
# else
variant_comp <- feature_data %>%
  dplyr::select(feature, group, count_rank, log_count, count, variant, fraction, pr_rem) %>%
  tidyr::spread(variant, pr_rem) %>%
  dplyr::mutate(biocar_bio = biocar - bio,
                car_bio = car - bio,
                bioesc_bio = bioesc - bio,
                esc_bio = esc - bio,
                bioesf_bio = bioesf - bio,
                esf_bio = esf - bio) %>%
  dplyr::select(count_rank, log_count, group, fraction, count, biocar_bio:esf_bio) %>%
  tidyr::gather(diff, value, -count_rank, -log_count, -count, -group, -fraction)

variant_comp_rl <- feature_data %>%
  dplyr::select(feature, status, count_rank, log_count, variant, pr_rem) %>%
  tidyr::spread(variant, pr_rem) %>%
  dplyr::mutate(biocar_bio = biocar - bio,
                car_bio = car - bio,
                bioesc_bio = bioesc - bio,
                esc_bio = esc - bio,
                bioesf_bio = bioesf - bio,
                esf_bio = esf - bio) %>%
  dplyr::select(count_rank, log_count, status, biocar_bio:esf_bio) %>%
  tidyr::gather(diff, value, -count_rank, -log_count, -status)

# Plot orderd coverage ----------------------------------------------------

# Order data by area

p1 <- ggplot(feature_data, aes(x = count_rank, y = pr_rem, frame = fraction)) +
  geom_point(alpha = 0.1) + geom_smooth(aes(group = fraction)) + 
  ylab("Proportion of range covered") +
  facet_wrap(~ variant, nrow = 4, ncol = 2) +
  ylim(c(0, 1)) + scale_x_discrete("Range rank (from smallest to largest)",
                                   limits = c(1, 763)) +
  theme_ipsum_rc()

gganimate(p1, ani.width = 1000, ani.height = 800, 
          filename = "reports/figures/diff_ordered_by_rank.gif")

#ggsave("reports/figures/diff_ordered_by_rank.png", p1, width = 6, height = 8)



# Plot diffs --------------------------------------------------------------

p2 <- ggplot(variant_comp, aes(x = count, y = value, frame = fraction)) +
  geom_point(alpha = 0.5, size = 0.5) + geom_smooth(aes(group = fraction), size = 0.7) +
  scale_color_brewer(type = "qual", palette = "Dark2") +
  scale_y_continuous(breaks = seq(-1, 0.25, 0.25),
                     labels = paste0(seq(-1, 0.25, 0.25) * 100, "%")) +
  ylab("Difference in proportion of range covered") +
  xlab("log(range size)") + facet_wrap(~ diff) + 
  theme_ipsum_rc() + theme(legend.position = "top", legend.title = element_blank())

# Wrap per group
#p3 <- p2 + facet_wrap(~ group)

gganimate(p2, ani.width = 1000, ani.height = 800,
          filename = "reports/figures/diff_ordered_by_area.gif")

p3 <- ggplot(variant_comp, aes(x = log_count, y = value, frame = fraction)) +
  geom_point(alpha = 0.5, size = 0.5) + geom_smooth(aes(group = fraction), size = 0.7) +
  scale_color_brewer(type = "qual", palette = "Dark2") +
  scale_y_continuous(breaks = seq(-1, 0.25, 0.25),
                     labels = paste0(seq(-1, 0.25, 0.25) * 100, "%")) +
  ylab("Difference in proportion of range covered") +
  xlab("log(range size)") + facet_wrap(~ diff) + 
  theme_ipsum_rc() + theme(legend.position = "top", legend.title = element_blank())

gganimate(p3, ani.width = 1000, ani.height = 800,
          filename = "reports/figures/diff_ordered_by_log_area.gif")

# ggsave("reports/figures/diff_ordered_by_area.png", p2,
#        width = 6, height = 6)
# ggsave("reports/figures/diff_ordered_by_area_group.png", p3,
#        width = 8, height = 6)

# Per red-list
p4 <- ggplot(variant_comp_rl, aes(x = log_count, y = value, color = diff)) +
  geom_point(alpha = 0.5, size = 0.5) + geom_smooth(size = 0.5) +
  scale_color_brewer(type = "qual", palette = "Dark2") +
  scale_y_continuous(breaks = seq(-1, 0.25, 0.25),
                     labels = paste0(seq(-1, 0.25, 0.25) * 100, "%")) +
  ylab("Difference in proportion of range covered") +
  xlab("log(range size)") +
  theme_ipsum_rc() + theme(legend.position = "top", legend.title = element_blank())

# Wrap per group
p5 <- p4 + facet_wrap(~ status)

ggsave("reports/figures/diff_ordered_by_area_rlstatus.png", p5,
       width = 10, height = 8)

