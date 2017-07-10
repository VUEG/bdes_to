library(dplyr)
library(ggplot2)
library(hrbrthemes)
library(readr)
library(tidyr)
library(zonator)
library(viridis)

# Helper functions --------------------------------------------------------

# panel.smooth function is built in.
# panel.cor puts correlation in upper panels, size proportional to correlation
panel.cor <- function(x, y, digits=2, prefix="", cex.cor, ...) {
  usr <- par("usr"); on.exit(par(usr))
  par(usr = c(0, 1, 0, 1))
  r <- abs(cor(x, y))
  txt <- format(c(r, 0.123456789), digits = digits)[1]
  txt <- paste(prefix, txt, sep = "")
  if (missing(cex.cor)) cex.cor <- 0.8/strwidth(txt)
  text(0.5, 0.5, txt, cex = cex.cor * r)
}


plot_pairs <- function(dat, taxon_name = NULL) {

  if (is.null(taxon_name)) {
    title <- "All taxa"
    dat <- dat %>%
      dplyr::select(log_count, log_mean_ol, morans_i, pr_rem)
  } else {
    title <- taxon_name
  }
  pairs(dat, lower.panel = panel.smooth, upper.panel = panel.cor,
        pch = 20, main = title)

}

# Load variants and configure groups --------------------------------------

zproject <- zonator::load_zproject('analyses/zonation/priocomp/')
# 04_abf_all_wgt

# Get performance for top 5% and Drop first (pr_lost) and last (cost)
# columns
v04_top10 <- zonator::get_variant(zproject, 4) %>%
  zonator::results() %>%
  zonator::performance(pr.lost = 0.9) %>%
  dplyr::select(-pr_lost, -pop_density_v5) %>%
  tidyr::gather(feature, pr_rem) %>%
  # Remove ES feautures
  dplyr::slice(10:n()) %>%
  dplyr::mutate(variant = "ALL")

v12_top10 <- zonator::get_variant(zproject, 12) %>%
  zonator::results() %>%
  zonator::performance(pr.lost = 0.9) %>%
  dplyr::select(-pr_lost, -pop_density_v5) %>%
  tidyr::gather(feature, pr_rem) %>%
  dplyr::mutate(variant = "BD")

v21_top10 <- zonator::get_variant(zproject, 21) %>%
  zonator::results() %>%
  zonator::performance(pr.lost = 0.9) %>%
  dplyr::select(-pr_lost, -pop_density_v5) %>%
  tidyr::gather(feature, pr_rem) %>%
  # Remove ES feautures
  dplyr::mutate(variant = "BD_rank_ES")

# Fix groups
new_groups <- c(rep("Amphibians", 83), rep("Birds", 404), rep("Mammals", 164),
                rep("Reptiles", 112))

# Load auxiliary data -----------------------------------------------------

feature_ranges <- readr::read_csv("data/feature_ranges.csv") %>%
  dplyr::select(feature_long = feature, dplyr::everything()) %>%
  dplyr::mutate(feature = gsub("\\.tif$", "", basename(feature_long))) %>%
  dplyr::select(feature, dplyr::everything(), -feature_long)

feature_autocor <- readr::read_csv("data/morans_I_values_772_features_2017-03-08_04-08-05.csv") %>%
  dplyr::mutate(feature = gsub("\\.tif$", "", basename(feature)))

feature_rl <- readr::read_csv("data/spp_rl_statuses.csv") %>%
  dplyr::mutate(feature = tolower(gsub("\\s", "_", species))) %>%
  dplyr::mutate(status = gsub("LR/nt", "NT", status)) %>%
  dplyr::mutate(status = factor(status, levels = c("DD", "LC", "NT", "VU", "EN", "CR")))

v04_feature_data <- v04_top10 %>%
  dplyr::left_join(feature_ranges) %>%
  dplyr::left_join(feature_autocor) %>%
  dplyr::left_join(feature_rl) %>%
  dplyr::mutate(log_count = log(count),
                log_mean_ol = log(mean_ol),
                count_rank = row_number(count),
                mean_ol_rank = row_number(-mean_ol))

v04_feature_data$group <- new_groups

v12_feature_data <- v12_top10 %>%
  dplyr::left_join(feature_ranges) %>%
  dplyr::left_join(feature_autocor) %>%
  dplyr::left_join(feature_rl) %>%
  dplyr::mutate(log_count = log(count),
                log_mean_ol = log(mean_ol),
                count_rank = row_number(count),
                mean_ol_rank = row_number(-mean_ol))

v12_feature_data$group <- new_groups

v21_feature_data <- v21_top10 %>%
  dplyr::left_join(feature_ranges) %>%
  dplyr::left_join(feature_autocor) %>%
  dplyr::left_join(feature_rl) %>%
  dplyr::mutate(log_count = log(count),
                log_mean_ol = log(mean_ol),
                count_rank = row_number(count),
                mean_ol_rank = row_number(-mean_ol))

v21_feature_data$group <- new_groups

all_feature_data <- dplyr::bind_rows(list(v12_feature_data, v04_feature_data,
                                          v21_feature_data))
all_feature_data$variant <- factor(all_feature_data$variant,
                                   levels = c("BD", "ALL", "BD_rank_ES"))

# Count differences between ranks in different variants
variant_comp <- all_feature_data %>%
  dplyr::select(feature, group, count_rank, log_count, variant, pr_rem) %>%
  tidyr::spread(variant, pr_rem) %>%
  dplyr::mutate(first_diff = ALL - BD,
                second_diff = BD_rank_ES - BD) %>%
  dplyr::select(count_rank, log_count, group, first_diff, second_diff) %>%
  tidyr::gather(diff, value, -count_rank, -log_count, -group) %>%
  dplyr::mutate(diff = factor(diff, levels = c("first_diff", "second_diff"),
                              labels = c("Between ALL and BD",
                                         "Between BD_rank_ES and BD")))

variant_comp_rl <- all_feature_data %>%
  dplyr::select(feature, status, count_rank, log_count, variant, pr_rem) %>%
  tidyr::spread(variant, pr_rem) %>%
  dplyr::mutate(first_diff = ALL - BD,
                second_diff = BD_rank_ES - BD) %>%
  dplyr::select(count_rank, log_count, status, first_diff, second_diff) %>%
  tidyr::gather(diff, value, -count_rank, -log_count, -status) %>%
  dplyr::mutate(diff = factor(diff, levels = c("first_diff", "second_diff"),
                              labels = c("Between ALL and BD",
                                         "Between BD_rank_ES and BD")))

# Plot cross-correlation matrix -------------------------------------------

p1 <- plot_pairs(dat = all_feature_data)


# Plot range size vs RL status --------------------------------------------

p1_1 <- ggplot(dplyr::filter(all_feature_data, variant == "ALL"),
               aes(x = status, y = log_count)) +
  geom_boxplot(varwidth = TRUE) + theme_ipsum_rc()

# Plot orderd coverage ----------------------------------------------------

# Order data by area

p3 <- ggplot(all_feature_data, aes(x = count_rank, y = pr_rem)) +
  geom_point(alpha = 0.1) + geom_smooth() + ylab("Proportion of range covered") +
  facet_wrap(~ variant, nrow = 1, ncol = 3) +
  ylim(c(0, 1)) + scale_x_discrete("Range rank (from smallest to largest)",
                                   limits = c(1, 763)) +
  theme_ipsum_rc()

ggsave("reports/figures/figureExtra/BD_coverage.png", p3,
       width = 10, height = 4)

# Plot diffs --------------------------------------------------------------

p4 <- ggplot(variant_comp, aes(x = log_count, y = value, color = diff)) +
  geom_point(alpha = 0.5, size = 0.5) + geom_smooth(size = 0.5) +
  scale_color_viridis(discrete = TRUE, end = 0.7) +
  scale_y_continuous(breaks = seq(-1, 0.25, 0.25),
                     labels = paste0(seq(-1, 0.25, 0.25) * 100, "%")) +
  ylab("Difference in proportion of range covered") +
  xlab("log(range size)") +
  theme_ipsum_rc() + theme(legend.position = "top", legend.title = element_blank())

# Wrap per group
p5 <- p4 + facet_wrap(~ group)

# Per red-list
p6 <- ggplot(variant_comp_rl, aes(x = log_count, y = value, color = diff)) +
  geom_point(alpha = 0.5, size = 0.5) + geom_smooth(size = 0.5) +
  scale_color_viridis(discrete = TRUE, end = 0.7) +
  scale_y_continuous(breaks = seq(-1, 0.25, 0.25),
                     labels = paste0(seq(-1, 0.25, 0.25) * 100, "%")) +
  ylab("Difference in proportion of range covered") +
  xlab("log(range size)") +
  theme_ipsum_rc() + theme(legend.position = "top", legend.title = element_blank())

# Wrap per group
p7 <- p6 + facet_wrap(~ status)

ggsave("reports/figures/figureExtra/BD_coverage_diff.png", p4,
       width = 6, height = 6)
ggsave("reports/figures/figureExtra/BD_coverage_diff_group.png", p5,
       width = 7, height = 7)

