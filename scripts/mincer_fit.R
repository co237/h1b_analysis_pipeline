# ==============================================================================
# Mincer-Based Individual H-1B Wage Gap Analysis
# ==============================================================================
# Fits a parametric Mincer wage equation on ACS native-born workers to estimate
# the native wage structure, then predicts what each H-1B worker would earn as
# a comparable native. Individual gaps let us report share positive/negative
# and gap magnitudes.
#
# Functional form (Murphy & Welch 1990, Lemieux 2006):
#   ln(wage) ~ education_dummies + X + X^2 + X^3 + X^4
# where X = potential experience = max(AGE - typical_schooling_years - 6, 0)
#
# Fit separately per 6-digit SOC occupation (fallback to 5-digit, 3-digit,
# 2-digit, then pooled if sample too small).
#
# Input:  data/processed/h1b_fy21_24_with_pumas.csv, IPUMS ACS microdata
# Output: output/tables/mincer_summary.csv, mincer_wage_gaps.csv
#         output/figures/mincer_01-04_*.png
# ==============================================================================

cat("\n")
cat("======================================================================\n")
cat("       MINCER WAGE EQUATION -- INDIVIDUAL H-1B WAGE GAPS\n")
cat("======================================================================\n\n")

# =============================================================================
# USER-CONFIGURABLE NPRM PARAMETERS
# =============================================================================
# Set the percentile thresholds for the NPRM proposed scenario (S4).
# Each value is the percentile of the ALL-WORKER occupation wage distribution
# that serves as the wage floor for H-1Bs at that DOL wage level.
# Change these to model alternative proposals.
nprm_L1 <- 35   # Level I   (entry-level)
nprm_L2 <- 53   # Level II  (qualified)
nprm_L3 <- 72   # Level III (experienced)
nprm_L4 <- 90   # Level IV  (fully competent / highly experienced)
# =============================================================================

# =============================================================================
# 1. Setup and Configuration
# =============================================================================

if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  setwd("..")
  source("config.R")
} else {
  stop("Cannot find config.R. Please run from project root or scripts/ directory")
}

# config.R's auto-detection can pick up the wrong directory (e.g. RStudio API
# returns active document's folder). It also creates directories, so we can't
# just check dir.exists(). Instead, check if the actual data file exists.
if (!file.exists(h1b_with_pumas_file)) {
  project_root <- getwd()
  data_dir <- file.path(project_root, "data")
  data_raw <- file.path(data_dir, "raw")
  data_intermediate <- file.path(data_dir, "intermediate")
  data_processed <- file.path(data_dir, "processed")
  output_dir <- file.path(project_root, "output")
  output_figures <- file.path(output_dir, "figures")
  output_tables <- file.path(output_dir, "tables")
  h1b_with_pumas_file <- file.path(data_processed, "h1b_fy21_24_with_pumas.csv")
  acs_ddi_file <- file.path(data_raw, "usa_00068.xml")
  soc_definitions_file <- file.path(data_raw, "soc_2018_definitions.xlsx")
  cat("Corrected project root to:", project_root, "\n")
}

library(ipumsr)
library(tidyverse)
library(readxl)
library(scales)
library(broom)

# Install fixest if not available (needed for PUMA FE spec)
if (!requireNamespace("fixest", quietly = TRUE)) {
  cat("Installing fixest package (needed for PUMA fixed effects)...\n")
  install.packages("fixest", repos = "https://cloud.r-project.org", quiet = TRUE)
}
use_fixest <- requireNamespace("fixest", quietly = TRUE)
if (use_fixest) {
  library(fixest)
  cat("fixest loaded successfully\n")
} else {
  cat("WARNING: fixest not available. PUMA specification will be skipped.\n")
}

# --- Education Code Mapping (same as 03_wage_premium_analysis.R) ---
map_education_code <- function(code) {
  case_when(
    code == "A" ~ 1L,
    code == "B" ~ 63L,
    code == "C" ~ 65L,
    code == "D" ~ 71L,
    code == "E" ~ 81L,
    code == "F" ~ 101L,
    code == "G" ~ 114L,
    code == "H" ~ 115L,
    code == "I" ~ 116L,
    TRUE ~ 0L
  )
}

# --- Education to typical years of schooling ---
educ_to_years <- function(educd) {
  case_when(
    educd == 1   ~ 10,   # Less than high school
    educd == 63  ~ 12,   # High school diploma
    educd == 65  ~ 14,   # Some college
    educd == 71  ~ 14,   # Associate's degree
    educd == 81  ~ 16,   # Bachelor's degree
    educd == 101 ~ 18,   # Master's degree
    educd == 114 ~ 19,   # Professional degree (JD, MD)
    educd == 115 ~ 20,   # Doctorate
    educd == 116 ~ 20,   # Doctorate (alternate)
    TRUE         ~ NA_real_
  )
}

# --- IFP Color Palette ---
ifp_colors <- list(
  off_white   = "#fcfbeb",
  purple      = "#b17ada",
  orange      = "#ff9762",
  rich_black  = "#373737",
  green       = "#39d794",
  red         = "#ff6565",
  light_blue  = "#41c4fc",
  yellow      = "#fbdb36",
  pink        = "#ff9ee3",
  dark_blue   = "#3368ce"
)

age_labels <- c(
  "[20,25)" = "20-24", "[25,30)" = "25-29", "[30,35)" = "30-34",
  "[35,40)" = "35-39", "[40,45)" = "40-44", "[45,50)" = "45-49",
  "[50,55)" = "50-54", "[55,60)" = "55-59", "[60,65)" = "60-64"
)

theme_h1b <- function() {
  theme_minimal() +
    theme(
      text = element_text(color = ifp_colors$rich_black),
      axis.text.x = element_text(angle = 30, hjust = 1, color = ifp_colors$rich_black),
      axis.text.y = element_text(color = ifp_colors$rich_black),
      axis.title = element_text(color = ifp_colors$rich_black),
      plot.caption = element_text(hjust = 0, margin = margin(t = 8), color = ifp_colors$rich_black),
      plot.title = element_text(size = 12, face = "bold", color = ifp_colors$rich_black),
      plot.subtitle = element_text(color = ifp_colors$rich_black),
      panel.grid.minor = element_blank(),
      legend.text = element_text(color = ifp_colors$rich_black),
      legend.title = element_text(color = ifp_colors$rich_black)
    )
}

save_plot <- function(plot_obj, filename, width = 10, height = 6) {
  filepath <- file.path(output_figures, filename)
  ggsave(filepath, plot = plot_obj, width = width, height = height, dpi = 300)
  cat("  Saved:", filename, "\n")
  return(invisible(plot_obj))
}

# =============================================================================
# 2. Data Loading
# =============================================================================

cat("--- Loading Data ---\n")

h1b_raw <- read.csv(h1b_with_pumas_file)
cat("H-1B records loaded:", nrow(h1b_raw), "\n")

ddi <- read_ipums_ddi(acs_ddi_file)
acs_raw <- read_ipums_micro(ddi)
cat("ACS records loaded:", nrow(acs_raw), "\n")

# =============================================================================
# 3. Data Cleaning and Panel Construction
# =============================================================================

cat("\n--- Building Panel ---\n")

# Clean H-1B data
h1b <- h1b_raw %>%
  transmute(
    YEAR = registration_lottery_year - 1,
    AGE = registration_lottery_year - registration_birth_year,
    OCCSOC = as.character(as.numeric(gsub("-", "", SOC_CODE))),
    EDUCD = map_education_code(petition_beneficiary_edu_code),
    INCWAGE = petition_annual_pay_clean,
    h1b_dependent = petition_employer_h1b_dependent,
    wage_level = wage_level_combined,
    PUMA = case_when(
      YEAR == 2021 ~ as.character(PUMA_2010),
      YEAR >= 2022 ~ as.character(PUMA_2020),
      TRUE ~ NA_character_
    ),
    PUMA_vintage = case_when(
      YEAR == 2021 ~ "2010",
      YEAR >= 2022 ~ "2020",
      TRUE ~ NA_character_
    ),
    H1B = 1L,
    PERWT = 1
  ) %>%
  filter(!is.na(AGE), INCWAGE > 0, YEAR >= 2021)

# Clean ACS data: native-born, employed, valid income
natives <- acs_raw %>%
  filter(
    CITIZEN %in% c(0, 1),
    INCWAGE > 0 & !INCWAGE %in% c(999998, 999999),
    EMPSTAT == 1,
    AGE >= 20, AGE < 65
  ) %>%
  transmute(
    YEAR,
    AGE,
    OCCSOC = as.character(OCCSOC),
    EDUCD = if_else(EDUCD == 64, 63L, if_else(EDUCD < 63, 1L, as.integer(EDUCD))),
    INCWAGE,
    h1b_dependent = NA_character_,
    wage_level = NA_character_,
    PUMA = if ("PUMA" %in% names(acs_raw) && "STATEFIP" %in% names(acs_raw)) {
      paste0(sprintf("%02d", as.integer(STATEFIP)), sprintf("%05d", as.integer(PUMA)))
    } else {
      NA_character_
    },
    PUMA_vintage = case_when(
      YEAR <= 2021 ~ "2010",
      YEAR >= 2022 ~ "2020",
      TRUE ~ NA_character_
    ),
    H1B = 0L,
    PERWT
  )

# Combine into panel
panel <- bind_rows(h1b, natives) %>%
  filter(INCWAGE > 0) %>%
  mutate(
    OCCSOC = as.character(OCCSOC),
    OCC2 = substr(OCCSOC, 1, 2),
    OCC3 = substr(OCCSOC, 1, 3),
    OCC5 = substr(OCCSOC, 1, 5),
    age_grp = cut(AGE, breaks = c(20, 25, 30, 35, 40, 45, 50, 55, 60, 65),
                  right = FALSE, include.lowest = TRUE)
  )

cat("Panel size:", nrow(panel), "\n")
cat("  H-1B:", sum(panel$H1B == 1), "\n")
cat("  Native-born:", sum(panel$H1B == 0), "\n")

# =============================================================================
# 4. Mincer Variable Construction
# =============================================================================

cat("\n--- Constructing Mincer Variables ---\n")

panel_mincer <- panel %>%
  mutate(
    EDUCD_int = as.integer(as.character(EDUCD)),
    S = educ_to_years(EDUCD_int),
    X = pmax(AGE - S - 6, 0),
    X2 = X^2,
    X3 = X^3,
    X4 = X^4,
    ln_wage = log(INCWAGE),
    EDUCD_f = factor(EDUCD_int)
  ) %>%
  filter(!is.na(S), !is.na(X), is.finite(ln_wage))

cat("Mincer panel (valid education + experience):", nrow(panel_mincer), "\n")
cat("  H-1B:", sum(panel_mincer$H1B == 1), "\n")
cat("  Native-born:", sum(panel_mincer$H1B == 0), "\n")
cat("  Mean years of schooling:", round(mean(panel_mincer$S), 1), "\n")
cat("  Mean potential experience:", round(mean(panel_mincer$X), 1), "\n\n")

# =============================================================================
# 4b. Compute Occupation Wage Percentiles from ALL ACS Workers
# =============================================================================
# Needed for NPRM wage floor analysis. Uses ALL employed ACS workers (not just
# native-born) because DOL wage levels are based on the full occupation
# wage distribution.

cat("--- Computing Occupation Wage Percentiles (all ACS workers) ---\n")

# Weighted quantile helper (no extra package dependency)
weighted_quantile <- function(x, w, probs) {
  ord <- order(x)
  x <- x[ord]; w <- w[ord]
  cum_w <- cumsum(w) / sum(w)
  sapply(probs, function(p) x[which.max(cum_w >= p)])
}

# Fixed percentiles for S1-S3 scenarios, combined with user-specified NPRM (S4)
all_pctile_ints <- sort(unique(c(17, 34, 50, 67,              # S1: status quo
                                 nprm_L1, nprm_L2, nprm_L3, nprm_L4)))  # S4: NPRM proposed
pctiles_needed <- all_pctile_ints / 100
pctile_names   <- paste0("p", all_pctile_ints)

# All employed ACS workers with valid income (no citizenship filter)
# Year-specific so each H-1B cohort is compared to its matched ACS year
acs_all_workers <- acs_raw %>%
  filter(
    INCWAGE > 0, !INCWAGE %in% c(999998, 999999),
    EMPSTAT == 1,
    AGE >= 20, AGE < 65
  ) %>%
  transmute(
    YEAR,
    OCCSOC = as.character(OCCSOC),
    OCC5 = substr(as.character(OCCSOC), 1, 5),
    OCC3 = substr(as.character(OCCSOC), 1, 3),
    INCWAGE, PERWT
  )

cat(sprintf("  All ACS workers for percentiles: %s\n", format(nrow(acs_all_workers), big.mark = ",")))

# 6-digit SOC percentiles by year
occ6_pctiles <- acs_all_workers %>%
  group_by(YEAR, OCCSOC) %>%
  filter(n() >= 30) %>%
  summarise(
    n_acs = n(),
    across_pctiles = list(weighted_quantile(INCWAGE, PERWT, pctiles_needed)),
    .groups = "drop"
  ) %>%
  mutate(across_pctiles = map(across_pctiles, ~ setNames(.x, pctile_names))) %>%
  unnest_wider(across_pctiles)

# 5-digit SOC percentiles by year (first fallback)
occ5_pctiles <- acs_all_workers %>%
  group_by(YEAR, OCC5) %>%
  filter(n() >= 30) %>%
  summarise(
    n_acs_5 = n(),
    across_pctiles = list(weighted_quantile(INCWAGE, PERWT, pctiles_needed)),
    .groups = "drop"
  ) %>%
  mutate(across_pctiles = map(across_pctiles, ~ setNames(.x, pctile_names))) %>%
  unnest_wider(across_pctiles)

# 3-digit SOC percentiles by year (second fallback)
occ3_pctiles <- acs_all_workers %>%
  group_by(YEAR, OCC3) %>%
  filter(n() >= 30) %>%
  summarise(
    n_acs_3 = n(),
    across_pctiles = list(weighted_quantile(INCWAGE, PERWT, pctiles_needed)),
    .groups = "drop"
  ) %>%
  mutate(across_pctiles = map(across_pctiles, ~ setNames(.x, pctile_names))) %>%
  unnest_wider(across_pctiles)

cat(sprintf("  6-digit YEAR x SOC cells with >=30 workers: %d\n", nrow(occ6_pctiles)))
cat(sprintf("  5-digit YEAR x SOC cells with >=30 workers: %d (fallback)\n", nrow(occ5_pctiles)))
cat(sprintf("  3-digit YEAR x SOC cells with >=30 workers: %d (fallback)\n\n", nrow(occ3_pctiles)))

rm(acs_all_workers)

# Free memory
rm(h1b_raw, acs_raw, ddi, h1b, natives, panel)
gc(verbose = FALSE)

# =============================================================================
# 5. Fit Mincer Equations by Occupation (Hierarchical)
# =============================================================================

cat("--- Fitting Mincer Equations by Occupation ---\n")

MIN_NATIVES <- 50  # minimum native-born obs to fit at a given occupation level

# Split data
natives_df <- panel_mincer %>% filter(H1B == 0)
h1b_df     <- panel_mincer %>% filter(H1B == 1)

# Count natives per occupation at each level
occ6_counts <- natives_df %>% count(OCCSOC, name = "n_natives_6")
occ5_counts <- natives_df %>% count(OCC5, name = "n_natives_5")
occ3_counts <- natives_df %>% count(OCC3, name = "n_natives_3")
occ2_counts <- natives_df %>% count(OCC2, name = "n_natives_2")

# Determine which level each H-1B gets matched at
h1b_df <- h1b_df %>%
  left_join(occ6_counts, by = "OCCSOC") %>%
  left_join(occ5_counts, by = "OCC5") %>%
  left_join(occ3_counts, by = "OCC3") %>%
  left_join(occ2_counts, by = "OCC2") %>%
  mutate(
    n_natives_6 = replace_na(n_natives_6, 0),
    n_natives_5 = replace_na(n_natives_5, 0),
    n_natives_3 = replace_na(n_natives_3, 0),
    n_natives_2 = replace_na(n_natives_2, 0),
    match_level = case_when(
      n_natives_6 >= MIN_NATIVES ~ "6-digit",
      n_natives_5 >= MIN_NATIVES ~ "5-digit",
      n_natives_3 >= MIN_NATIVES ~ "3-digit",
      n_natives_2 >= MIN_NATIVES ~ "2-digit",
      TRUE ~ "pooled"
    ),
    match_occ = case_when(
      match_level == "6-digit" ~ OCCSOC,
      match_level == "5-digit" ~ OCC5,
      match_level == "3-digit" ~ OCC3,
      match_level == "2-digit" ~ OCC2,
      TRUE ~ "ALL"
    )
  )

cat("H-1B match levels:\n")
cat("  6-digit SOC:", sum(h1b_df$match_level == "6-digit"), "\n")
cat("  5-digit SOC:", sum(h1b_df$match_level == "5-digit"), "\n")
cat("  3-digit SOC:", sum(h1b_df$match_level == "3-digit"), "\n")
cat("  2-digit SOC:", sum(h1b_df$match_level == "2-digit"), "\n")
cat("  Pooled:     ", sum(h1b_df$match_level == "pooled"), "\n\n")

# --- Helper: fit Mincer without PUMA FE (fallback for small occupations) ---
fit_and_predict_nopuma <- function(native_subset, h1b_subset) {
  # Murphy-Welch quartic with education dummies, no geographic controls
  n_educ_levels <- n_distinct(native_subset$EDUCD_f)
  
  rhs_parts <- c("X", "X2", "X3", "X4")
  if (n_educ_levels > 1) rhs_parts <- c(rhs_parts, "EDUCD_f")
  
  fml <- as.formula(paste("ln_wage ~", paste(rhs_parts, collapse = " + ")))
  
  fit <- tryCatch(
    lm(fml, data = native_subset, weights = PERWT),
    error = function(e) NULL
  )
  
  if (is.null(fit)) return(rep(NA_real_, nrow(h1b_subset)))
  
  tryCatch(
    predict(fit, newdata = h1b_subset),
    error = function(e) rep(NA_real_, nrow(h1b_subset)))
}

# --- Primary helper: fit Mincer with PUMA FE (falls back to no-PUMA) ---
fit_and_predict <- function(native_subset, h1b_subset) {
  # Murphy-Welch quartic + education dummies + PUMA FE
  # Controls for experience, education, and local labor market
  n_educ_levels <- n_distinct(native_subset$EDUCD_f)
  n_puma_levels <- n_distinct(native_subset$PUMA[!is.na(native_subset$PUMA)])
  
  # Need enough PUMAs to justify FE; otherwise fall back to no-PUMA
  if (!use_fixest || n_puma_levels < 3 || nrow(native_subset) < 100) {
    return(fit_and_predict_nopuma(native_subset, h1b_subset))
  }
  
  # Build fixest formula: covariates | PUMA fixed effects
  rhs_parts <- c("X", "X2", "X3", "X4")
  if (n_educ_levels > 1) rhs_parts <- c(rhs_parts, "EDUCD_f")
  
  fml <- as.formula(paste("ln_wage ~", paste(rhs_parts, collapse = " + "), "| PUMA"))
  
  fit <- tryCatch(
    feols(fml, data = native_subset, weights = ~PERWT, notes = FALSE, warn = FALSE),
    error = function(e) NULL
  )
  
  if (is.null(fit)) return(fit_and_predict_nopuma(native_subset, h1b_subset))
  
  tryCatch(
    predict(fit, newdata = h1b_subset),
    error = function(e) fit_and_predict_nopuma(native_subset, h1b_subset)
  )
}

# --- Fit helper: run one spec across all occupation levels ---
run_spec <- function(h1b_data, natives_data, fit_fn, spec_name,
                     occ6, occ5, occ3, occ2) {
  cat(sprintf("=== %s ===\n", spec_name))
  
  pred_col <- rep(NA_real_, nrow(h1b_data))
  
  # 6-digit level
  cat(sprintf("  Fitting %d 6-digit occupation models...\n", length(occ6)))
  for (i in seq_along(occ6)) {
    occ <- occ6[i]
    idx <- which(h1b_data$OCCSOC == occ & h1b_data$match_level == "6-digit")
    if (length(idx) == 0) next
    native_sub <- natives_data %>% filter(OCCSOC == occ)
    pred_col[idx] <- fit_fn(native_sub, h1b_data[idx, ])
    if (i %% 50 == 0 || i == length(occ6))
      cat(sprintf("    [%d/%d] occupations fitted\r", i, length(occ6)))
  }
  cat("\n")
  
  # 5-digit level
  cat(sprintf("  Fitting %d 5-digit occupation models...\n", length(occ5)))
  for (occ in occ5) {
    idx <- which(h1b_data$OCC5 == occ & h1b_data$match_level == "5-digit")
    if (length(idx) == 0) next
    native_sub <- natives_data %>% filter(OCC5 == occ)
    pred_col[idx] <- fit_fn(native_sub, h1b_data[idx, ])
  }
  
  # 3-digit level
  cat(sprintf("  Fitting %d 3-digit occupation models...\n", length(occ3)))
  for (occ in occ3) {
    idx <- which(h1b_data$OCC3 == occ & h1b_data$match_level == "3-digit")
    if (length(idx) == 0) next
    native_sub <- natives_data %>% filter(OCC3 == occ)
    pred_col[idx] <- fit_fn(native_sub, h1b_data[idx, ])
  }
  
  # 2-digit level
  cat(sprintf("  Fitting %d 2-digit occupation models...\n", length(occ2)))
  for (occ in occ2) {
    idx <- which(h1b_data$OCC2 == occ & h1b_data$match_level == "2-digit")
    if (length(idx) == 0) next
    native_sub <- natives_data %>% filter(OCC2 == occ)
    pred_col[idx] <- fit_fn(native_sub, h1b_data[idx, ])
  }
  
  # Pooled
  pooled_idx <- which(h1b_data$match_level == "pooled")
  if (length(pooled_idx) > 0) {
    cat(sprintf("  Fitting pooled model for %d remaining H-1Bs...\n", length(pooled_idx)))
    pred_col[pooled_idx] <- fit_fn(natives_data, h1b_data[pooled_idx, ])
  }
  
  # Compute gaps
  predicted_wage <- exp(pred_col)
  gap <- h1b_data$INCWAGE - predicted_wage
  n_valid <- sum(!is.na(gap))
  share_pos <- mean(gap > 0, na.rm = TRUE)
  avg_gap_val <- mean(gap, na.rm = TRUE)
  med_gap_val <- median(gap, na.rm = TRUE)
  
  cat(sprintf("\n%s Results:\n", spec_name))
  cat(sprintf("  Valid predictions: %s / %s (%.1f%%)\n",
              format(n_valid, big.mark = ","),
              format(nrow(h1b_data), big.mark = ","),
              n_valid / nrow(h1b_data) * 100))
  cat(sprintf("  Share with positive gap: %.1f%%\n", share_pos * 100))
  cat(sprintf("  Average gap: $%s\n", format(round(avg_gap_val), big.mark = ",")))
  cat(sprintf("  Median gap: $%s\n\n", format(round(med_gap_val), big.mark = ",")))
  
  list(predicted_ln_wage = pred_col, predicted_wage = predicted_wage,
       gap = gap, log_gap = h1b_df$ln_wage - pred_col,
       n_valid = n_valid, share_pos = share_pos,
       avg_gap = avg_gap_val, med_gap = med_gap_val)
}

# Get unique occupation groups to fit
occ_groups_6 <- unique(h1b_df$OCCSOC[h1b_df$match_level == "6-digit"])
occ_groups_5 <- unique(h1b_df$OCC5[h1b_df$match_level == "5-digit"])
occ_groups_3 <- unique(h1b_df$OCC3[h1b_df$match_level == "3-digit"])
occ_groups_2 <- unique(h1b_df$OCC2[h1b_df$match_level == "2-digit"])

# --- Spec 1: Experience + Education (no PUMA FE) ---
spec1 <- run_spec(h1b_df, natives_df, fit_and_predict_nopuma,
                  "Spec 1: Experience + Education (national)",
                  occ_groups_6, occ_groups_5, occ_groups_3, occ_groups_2)

h1b_df$predicted_ln_wage_1 <- spec1$predicted_ln_wage
h1b_df$predicted_wage_1    <- spec1$predicted_wage
h1b_df$gap_1               <- spec1$gap
h1b_df$log_gap_1           <- spec1$log_gap

# --- Spec 2: Experience + Education + PUMA FE ---
spec2 <- run_spec(h1b_df, natives_df, fit_and_predict,
                  "Spec 2: Experience + Education + PUMA FE",
                  occ_groups_6, occ_groups_5, occ_groups_3, occ_groups_2)

h1b_df$predicted_ln_wage_2 <- spec2$predicted_ln_wage
h1b_df$predicted_wage_2    <- spec2$predicted_wage
h1b_df$gap_2               <- spec2$gap
h1b_df$log_gap_2           <- spec2$log_gap

# =============================================================================
# 5b. Model Diagnostics for Top H-1B Occupations
# =============================================================================

cat("\n=== Model Fit Diagnostics for Top H-1B Occupations ===\n")

# Load SOC labels
soc_codes <- read_excel(soc_definitions_file, skip = 7) %>%
  mutate(soc_numeric = str_remove_all(`SOC Code`, "-") %>% as.numeric()) %>%
  filter(`SOC Group` == "Detailed") %>%
  transmute(OCCSOC = as.character(soc_numeric), occ_title = `SOC Title`)

# Identify top H-1B occupations (by H-1B count, 6-digit level only)
top_occs <- h1b_df %>%
  filter(match_level == "6-digit") %>%
  count(OCCSOC, sort = TRUE) %>%
  head(30) %>%
  left_join(soc_codes, by = "OCCSOC") %>%
  rename(n_h1b = n)

# Re-fit each top occupation and collect diagnostics
occ_diagnostics <- list()

for (i in 1:nrow(top_occs)) {
  occ <- top_occs$OCCSOC[i]
  occ_title <- top_occs$occ_title[i]
  n_h1b <- top_occs$n_h1b[i]
  
  native_sub <- natives_df %>% filter(OCCSOC == occ)
  h1b_sub <- h1b_df %>% filter(OCCSOC == occ, match_level == "6-digit")
  n_native <- nrow(native_sub)
  
  # Build formula (same logic as fit_and_predict)
  n_educ_levels <- n_distinct(native_sub$EDUCD_f)
  rhs_parts <- c("X", "X2", "X3", "X4")
  if (n_educ_levels > 1) rhs_parts <- c(rhs_parts, "EDUCD_f")
  fml <- as.formula(paste("ln_wage ~", paste(rhs_parts, collapse = " + ")))
  
  fit <- tryCatch(lm(fml, data = native_sub, weights = PERWT), error = function(e) NULL)
  
  if (is.null(fit)) next
  
  fit_summary <- summary(fit)
  fit_glance <- glance(fit)
  fit_tidy <- tidy(fit)
  
  # Extract experience coefficients
  x_coefs <- fit_tidy %>% filter(term %in% c("X", "X2", "X3", "X4"))
  
  # Predict for H-1Bs and compute gap stats within this occupation
  h1b_preds <- tryCatch(predict(fit, newdata = h1b_sub), error = function(e) NULL)
  
  share_pos_occ <- NA_real_
  avg_gap_occ <- NA_real_
  med_gap_occ <- NA_real_
  n_predicted <- 0
  if (!is.null(h1b_preds)) {
    gaps_occ <- h1b_sub$INCWAGE - exp(h1b_preds)
    valid <- !is.na(gaps_occ)
    n_predicted <- sum(valid)
    if (n_predicted > 0) {
      share_pos_occ <- mean(gaps_occ[valid] > 0)
      avg_gap_occ <- mean(gaps_occ[valid])
      med_gap_occ <- median(gaps_occ[valid])
    }
  }
  
  occ_diagnostics[[i]] <- tibble(
    OCCSOC = occ,
    Title = occ_title,
    N_Natives = n_native,
    N_H1B = n_h1b,
    N_Predicted = n_predicted,
    R2 = fit_glance$r.squared,
    Adj_R2 = fit_glance$adj.r.squared,
    RMSE = sqrt(mean(fit$residuals^2)),
    N_Coefficients = length(fit$coefficients),
    F_Statistic = fit_glance$statistic,
    X_linear = x_coefs$estimate[x_coefs$term == "X"],
    X_linear_p = x_coefs$p.value[x_coefs$term == "X"],
    Share_Positive = share_pos_occ,
    Avg_Gap = avg_gap_occ,
    Median_Gap = med_gap_occ
  )
}

occ_diag_table <- bind_rows(occ_diagnostics)

# Print the diagnostics table
cat("\n")
cat(sprintf("%-45s %7s %7s %6s %6s %8s  %6s  %8s\n",
            "Occupation", "Native", "H-1B", "R2", "AdjR2", "RMSE",
            "%Pos", "Med Gap"))
cat(paste(rep("-", 110), collapse = ""), "\n")

for (i in 1:nrow(occ_diag_table)) {
  row <- occ_diag_table[i, ]
  title_short <- substr(row$Title, 1, 44)
  cat(sprintf("%-45s %7s %7s %5.3f %5.3f %8.4f  %5.1f%%  $%7s\n",
              title_short,
              format(row$N_Natives, big.mark = ","),
              format(row$N_H1B, big.mark = ","),
              row$R2, row$Adj_R2, row$RMSE,
              row$Share_Positive * 100,
              format(round(row$Median_Gap), big.mark = ",")))
}

cat("\n")
cat("Note: R2 is from Mincer fit on native-born workers only.\n")
cat("RMSE is in log-wage units (e.g., 0.50 ~ wages vary by ~50% around prediction).\n\n")

# Save diagnostics CSV
write.csv(occ_diag_table, file.path(output_tables, "mincer_occ_diagnostics.csv"), row.names = FALSE)
cat("Saved: output/tables/mincer_occ_diagnostics.csv\n")

# --- Figure: R2 by occupation for top occupations ---
p_diag <- occ_diag_table %>%
  mutate(Title_short = str_trunc(Title, 40),
         Title_short = fct_reorder(Title_short, R2)) %>%
  ggplot(aes(x = R2, y = Title_short)) +
  geom_point(aes(size = N_Natives), color = ifp_colors$dark_blue, alpha = 0.8) +
  geom_vline(xintercept = median(occ_diag_table$R2, na.rm = TRUE),
             linetype = "dashed", color = "gray50") +
  scale_size_continuous(name = "Native N",
                        labels = function(x) format(x, big.mark = ","),
                        range = c(1.5, 6)) +
  scale_x_continuous(labels = percent, limits = c(0, max(occ_diag_table$R2, na.rm = TRUE) * 1.1)) +
  labs(
    title = "Mincer Model R-squared for Top 30 H-1B Occupations",
    subtitle = "Fit on native-born workers; Murphy-Welch quartic + education dummies",
    x = expression(R^2),
    y = NULL,
    caption = "Source: 2021-2023 ACS via IPUMS. Point size = native-born sample size."
  ) +
  theme_h1b() +
  theme(axis.text.x = element_text(angle = 0, hjust = 0.5))
save_plot(p_diag, "mincer_05_occ_diagnostics.png", width = 12, height = 9)

# =============================================================================
# 6. Summary Table
# =============================================================================

cat("\n--- Building Summary Table ---\n")

summary_rows <- list(
  tibble(
    Specification = "Mincer: Exp + Education (national)",
    Sample_Size = spec1$n_valid,
    Share_Positive = spec1$share_pos,
    Avg_Gap = spec1$avg_gap,
    Median_Gap = spec1$med_gap
  ),
  tibble(
    Specification = "Mincer: Exp + Education + PUMA FE",
    Sample_Size = spec2$n_valid,
    Share_Positive = spec2$share_pos,
    Avg_Gap = spec2$avg_gap,
    Median_Gap = spec2$med_gap
  )
)

summary_table <- bind_rows(summary_rows)

# Also add breakdowns by match level for Spec 2 (primary)
match_summary <- h1b_df %>%
  filter(!is.na(gap_2)) %>%
  group_by(match_level) %>%
  summarise(
    N = n(),
    Share_Positive = mean(gap_2 > 0),
    Avg_Gap = mean(gap_2),
    Median_Gap = median(gap_2),
    .groups = "drop"
  ) %>%
  arrange(factor(match_level, levels = c("6-digit", "5-digit", "3-digit", "2-digit", "pooled")))

cat("\nSpec 2 (with PUMA FE) by match level:\n")
for (i in 1:nrow(match_summary)) {
  row <- match_summary[i, ]
  cat(sprintf("  %s: N=%s, %.1f%% positive, avg gap $%s\n",
              row$match_level,
              format(row$N, big.mark = ","),
              row$Share_Positive * 100,
              format(round(row$Avg_Gap), big.mark = ",")))
}

# Save summary CSV
summary_out <- summary_table %>%
  mutate(
    Share_Positive = sprintf("%.1f%%", Share_Positive * 100),
    Avg_Gap = sprintf("$%s", format(round(Avg_Gap), big.mark = ",")),
    Median_Gap = sprintf("$%s", format(round(Median_Gap), big.mark = ",")),
    Sample_Size = format(Sample_Size, big.mark = ",")
  )

write.csv(summary_out, file.path(output_tables, "mincer_summary.csv"), row.names = FALSE)
cat("\nSaved: output/tables/mincer_summary.csv\n")

# =============================================================================
# 7. Export Individual Wage Gaps
# =============================================================================

cat("\n--- Exporting Individual Wage Gaps ---\n")

export_cols <- c("YEAR", "AGE", "OCCSOC", "OCC5", "OCC3", "OCC2", "EDUCD_int",
                 "S", "X", "INCWAGE", "h1b_dependent", "wage_level",
                 "match_level", "match_occ",
                 "predicted_wage_1", "gap_1", "log_gap_1",
                 "predicted_wage_2", "gap_2", "log_gap_2")

gaps_export <- h1b_df %>% select(all_of(export_cols))

write.csv(gaps_export, file.path(output_tables, "mincer_wage_gaps.csv"), row.names = FALSE)
cat(sprintf("Saved: output/tables/mincer_wage_gaps.csv (%s rows)\n",
            format(nrow(gaps_export), big.mark = ",")))

# =============================================================================
# 8. Figures
# =============================================================================

cat("\n=== Generating Figures ===\n")

# Use Spec 2 (with PUMA FE) as primary
h1b_plot <- h1b_df %>% filter(!is.na(gap_2))

# --- Figure 1: Summary comparison (Mincer vs cell-median) ---
# Load existing cell-median results if available
cell_median_file <- file.path(output_tables, "summary_by_control.csv")
if (file.exists(cell_median_file)) {
  cell_median <- read.csv(cell_median_file, stringsAsFactors = FALSE)
  
  comparison_data <- bind_rows(
    tibble(
      Method = "Cell Median",
      Control = c("Age Only", "Age + Education", "Age + Occupation",
                  "Full (Age+Ed+Occ)", "Full + PUMA"),
      Share_Positive = as.numeric(gsub("[%]", "", cell_median$Share.Positive)) / 100
    ),
    tibble(
      Method = "Mincer",
      Control = c("Exp + Educ", "Exp + Educ + PUMA"),
      Share_Positive = c(spec1$share_pos, spec2$share_pos)
    )
  ) %>%
    mutate(Control = factor(Control, levels = unique(Control)))
  
  p1 <- ggplot(comparison_data, aes(x = Control, y = Share_Positive, fill = Method)) +
    geom_col(position = "dodge", width = 0.7) +
    geom_text(aes(label = percent(Share_Positive, accuracy = 0.1)),
              position = position_dodge(width = 0.7), vjust = -0.4, size = 3) +
    scale_y_continuous(labels = percent, limits = c(0, 1.1),
                       expand = expansion(mult = c(0, 0.05))) +
    scale_fill_manual(values = c("Cell Median" = ifp_colors$light_blue,
                                 "Mincer" = ifp_colors$dark_blue)) +
    labs(
      title = "Share of H-1B Workers Earning More Than Comparable Natives",
      subtitle = "Cell-median approach vs. Mincer regression prediction",
      x = NULL, y = "Share with positive wage gap",
      caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS\nMincer: Murphy-Welch quartic, education dummies, fit per 6-digit SOC"
    ) +
    theme_h1b() +
    theme(legend.position = "top")
  save_plot(p1, "mincer_01_summary_comparison.png", width = 12, height = 7)
}

# --- Figure 2: Distribution of individual wage gaps ---
p2 <- ggplot(h1b_plot, aes(x = gap_2 / 1000)) +
  geom_histogram(binwidth = 5, fill = ifp_colors$dark_blue, color = "white",
                 alpha = 0.8, boundary = 0) +
  geom_vline(xintercept = 0, linetype = "dashed", color = ifp_colors$red, linewidth = 0.8) +
  annotate("text", x = spec2$med_gap / 1000, y = Inf, vjust = 2,
           label = sprintf("Median: $%sk", round(spec2$med_gap / 1000, 1)),
           color = ifp_colors$rich_black, size = 3.5) +
  scale_x_continuous(limits = c(-150, 200), labels = function(x) paste0("$", x, "k")) +
  labs(
    title = "Distribution of Individual H-1B Wage Gaps (Mincer Prediction)",
    subtitle = sprintf("%.1f%% of H-1Bs earn more than their predicted native-equivalent wage",
                       spec2$share_pos * 100),
    x = "Wage gap (actual H-1B wage - predicted native wage, $thousands)",
    y = "Number of H-1B workers",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS\nMincer: Murphy-Welch quartic, education dummies, fit per 6-digit SOC"
  ) +
  theme_h1b()
save_plot(p2, "mincer_02_gap_distribution.png")

# --- Figure 3: Share positive by age group ---
age_gaps <- h1b_plot %>%
  group_by(age_grp) %>%
  summarise(
    share_positive = mean(gap_2 > 0),
    avg_gap = mean(gap_2),
    n = n(),
    .groups = "drop"
  ) %>%
  filter(!is.na(age_grp))

p3 <- ggplot(age_gaps, aes(x = age_grp, y = share_positive)) +
  geom_col(width = 0.8, fill = ifp_colors$dark_blue) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)), vjust = -0.4, size = 3.5) +
  geom_hline(yintercept = 0.5, linetype = "dotted", color = "gray50") +
  scale_y_continuous(labels = percent, limits = c(0, 1),
                     expand = expansion(mult = c(0, 0.08))) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "Share of H-1Bs Earning More Than Predicted Native Wage, by Age",
    subtitle = "Mincer prediction: occupation-specific, education + quartic experience",
    x = "Age of H-1B recipient",
    y = "Share with positive wage gap",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()
save_plot(p3, "mincer_03_gap_by_age.png")

# --- Figure 4: Share positive by DOL wage level ---
wl_gaps <- h1b_plot %>%
  filter(wage_level %in% c("I", "II", "III", "IV")) %>%
  group_by(wage_level) %>%
  summarise(
    share_positive = mean(gap_2 > 0),
    avg_gap = mean(gap_2),
    n = n(),
    .groups = "drop"
  )

p4 <- ggplot(wl_gaps, aes(x = wage_level, y = share_positive)) +
  geom_col(width = 0.7, fill = c(ifp_colors$light_blue, ifp_colors$purple,
                                 ifp_colors$dark_blue, ifp_colors$rich_black)) +
  geom_text(aes(label = sprintf("%s\n(n=%s)", percent(share_positive, accuracy = 1),
                                format(n, big.mark = ","))),
            vjust = -0.3, size = 3.2) +
  geom_hline(yintercept = 0.5, linetype = "dotted", color = "gray50") +
  scale_y_continuous(labels = percent, limits = c(0, 1.15),
                     expand = expansion(mult = c(0, 0))) +
  labs(
    title = "Share of H-1Bs Earning More Than Predicted Native Wage, by DOL Wage Level",
    subtitle = "Level I = entry, Level IV = highly experienced",
    x = "DOL Wage Level",
    y = "Share with positive wage gap",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS\nMincer: Murphy-Welch quartic, education dummies, fit per 6-digit SOC"
  ) +
  theme_h1b()
save_plot(p4, "mincer_04_gap_by_wage_level.png")

# =============================================================================
# 10. NPRM Wage Floor Counterfactual Analysis
# =============================================================================

cat("\n")
cat("======================================================================\n")
cat("       NPRM WAGE FLOOR COUNTERFACTUAL ANALYSIS\n")
cat("======================================================================\n\n")

# Use sample with valid predictions for BOTH specs (apples-to-apples)
h1b_nprm <- h1b_df %>% filter(!is.na(gap_1) & !is.na(gap_2))
baseline_n <- nrow(h1b_nprm)
baseline_underpaid_1 <- mean(h1b_nprm$gap_1 < 0)
baseline_underpaid_2 <- mean(h1b_nprm$gap_2 < 0)

cat(sprintf("Baseline: %s H-1Bs with valid predictions for both specs\n",
            format(baseline_n, big.mark = ",")))
cat(sprintf("  Spec 1 (no geo FE):   %.1f%% underpaid\n", baseline_underpaid_1 * 100))
cat(sprintf("  Spec 2 (with PUMA FE): %.1f%% underpaid\n\n", baseline_underpaid_2 * 100))

# --- Merge year-specific occupation percentile floors onto H-1B data ---
# Prefer 6-digit; fall back to 5-digit, then 3-digit. Joined by YEAR so
# each H-1B cohort is compared to its matched ACS year.
h1b_nprm <- h1b_nprm %>%
  left_join(occ6_pctiles %>% select(YEAR, OCCSOC, starts_with("p")),
            by = c("YEAR", "OCCSOC"), suffix = c("", "_6")) %>%
  left_join(occ5_pctiles %>% select(YEAR, OCC5, starts_with("p")),
            by = c("YEAR", "OCC5"), suffix = c("", "_5")) %>%
  left_join(occ3_pctiles %>% select(YEAR, OCC3, starts_with("p")),
            by = c("YEAR", "OCC3"), suffix = c("", "_3"))

# For each percentile column, use 6-digit if available, else 5-digit, else 3-digit
for (pn in pctile_names) {
  col_5 <- paste0(pn, "_5")
  col_3 <- paste0(pn, "_3")
  h1b_nprm[[pn]] <- if_else(is.na(h1b_nprm[[pn]]), h1b_nprm[[col_5]], h1b_nprm[[pn]])
  h1b_nprm[[pn]] <- if_else(is.na(h1b_nprm[[pn]]), h1b_nprm[[col_3]], h1b_nprm[[pn]])
}
# Drop the fallback columns
h1b_nprm <- h1b_nprm %>% select(-ends_with("_5"), -ends_with("_3"))

cat(sprintf("H-1Bs with occupation percentile data: %s / %s (%.1f%%)\n\n",
            format(sum(!is.na(h1b_nprm$p50)), big.mark = ","),
            format(baseline_n, big.mark = ","),
            sum(!is.na(h1b_nprm$p50)) / baseline_n * 100))

# --- Define scenarios ---
# Each scenario computes a wage floor per H-1B worker
h1b_nprm <- h1b_nprm %>%
  mutate(
    # Scenario 1: STATUS QUO level-specific (I→17th, II→34th, III→50th, IV→67th)
    floor_s1 = case_when(
      wage_level == "I"   ~ p17,
      wage_level == "II"  ~ p34,
      wage_level == "III" ~ p50,
      wage_level == "IV"  ~ p67,
      TRUE ~ NA_real_
    ),
    # # Scenario 2: flat floor at 34th percentile of occupation (commented out)
    # floor_s2 = p34,
    # Scenario 2: flat floor at 50th percentile of occupation (occ median)
    floor_s2 = p50,
    # Scenario 4: NPRM proposed level-specific (user-configurable, see top of script)
    floor_s4 = case_when(
      wage_level == "I"   ~ .data[[paste0("p", nprm_L1)]],
      wage_level == "II"  ~ .data[[paste0("p", nprm_L2)]],
      wage_level == "III" ~ .data[[paste0("p", nprm_L3)]],
      wage_level == "IV"  ~ .data[[paste0("p", nprm_L4)]],
      TRUE ~ NA_real_
    )
  )

# --- Run each scenario (reporting both specs) ---
run_scenario <- function(data, floor_col, name) {
  floor_vals <- data[[floor_col]]
  has_floor <- !is.na(floor_vals)
  eligible <- has_floor & (data$INCWAGE >= floor_vals)
  
  n_with_floor <- sum(has_floor)
  n_eligible <- sum(eligible)
  n_screened <- n_with_floor - n_eligible
  pct_screened <- n_screened / n_with_floor * 100
  
  # Share underpaid among eligible under each spec
  underpaid_1 <- mean(data$gap_1[eligible] < 0)
  underpaid_2 <- mean(data$gap_2[eligible] < 0)
  
  cat(sprintf("%-45s  %7s / %7s  Scrn: %5.1f%%  NoGeo: %5.1f%%  PUMA: %5.1f%%\n",
              name,
              format(n_eligible, big.mark = ","),
              format(n_with_floor, big.mark = ","),
              pct_screened, underpaid_1 * 100, underpaid_2 * 100))
  
  tibble(
    Scenario = name,
    N_With_Floor = n_with_floor,
    N_Eligible = n_eligible,
    N_Screened = n_screened,
    Pct_Screened = pct_screened,
    Underpaid_NoGeo = underpaid_1,
    Underpaid_PUMA = underpaid_2
  )
}

cat(sprintf("%-45s  %17s  %9s  %8s  %8s\n",
            "Scenario", "Eligible / Pool", "Screened", "No Geo", "PUMA FE"))
cat(paste(rep("-", 105), collapse = ""), "\n")

# Baseline row (no floor)
baseline_row <- tibble(
  Scenario = "Baseline (no wage floor)",
  N_With_Floor = baseline_n,
  N_Eligible = baseline_n,
  N_Screened = 0L,
  Pct_Screened = 0,
  Underpaid_NoGeo = baseline_underpaid_1,
  Underpaid_PUMA = baseline_underpaid_2
)
cat(sprintf("%-45s  %7s / %7s  Scrn: %5.1f%%  NoGeo: %5.1f%%  PUMA: %5.1f%%\n",
            "Baseline (no wage floor)",
            format(baseline_n, big.mark = ","),
            format(baseline_n, big.mark = ","),
            0.0, baseline_underpaid_1 * 100, baseline_underpaid_2 * 100))

s1 <- run_scenario(h1b_nprm, "floor_s1", "S1: Status quo (17/34/50/67th)")
# s2_34 <- run_scenario(h1b_nprm, "floor_s2", "S2: Floor at 34th pctile")  # commented out
s2 <- run_scenario(h1b_nprm, "floor_s2", "S2: Floor at 50th pctile (occ median)")
s3_label <- sprintf("S3: NPRM proposed (%d/%d/%d/%dth)", nprm_L1, nprm_L2, nprm_L3, nprm_L4)
s3 <- run_scenario(h1b_nprm, "floor_s4", s3_label)

nprm_results <- bind_rows(baseline_row, s1, s2, s3)

# --- Save NPRM table ---
nprm_out <- nprm_results %>%
  mutate(
    Pct_Screened = sprintf("%.1f%%", Pct_Screened),
    Underpaid_NoGeo = sprintf("%.1f%%", Underpaid_NoGeo * 100),
    Underpaid_PUMA = sprintf("%.1f%%", Underpaid_PUMA * 100),
    N_With_Floor = format(N_With_Floor, big.mark = ","),
    N_Eligible = format(N_Eligible, big.mark = ","),
    N_Screened = format(N_Screened, big.mark = ",")
  )
write.csv(nprm_out, file.path(output_tables, "nprm_wage_floor_analysis.csv"), row.names = FALSE)
cat("\nSaved: output/tables/nprm_wage_floor_analysis.csv\n")

# --- Figure 6: NPRM scenario comparison (both specs) ---
scenario_labels <- c("Baseline\n(no floor)",
                     "S1: Status quo\n(17/34/50/67)",
                     "S2: 50th pctile\n(occ median)",
                     sprintf("S3: NPRM proposed\n(%d/%d/%d/%d)", nprm_L1, nprm_L2, nprm_L3, nprm_L4))

p6_data <- nprm_results %>%
  mutate(Scenario_short = factor(scenario_labels, levels = scenario_labels)) %>%
  pivot_longer(cols = c(Underpaid_NoGeo, Underpaid_PUMA),
               names_to = "Spec", values_to = "Share_Underpaid") %>%
  mutate(Spec = if_else(Spec == "Underpaid_NoGeo",
                        "No geographic FE", "With PUMA FE"))

p6 <- ggplot(p6_data, aes(x = Scenario_short, y = Share_Underpaid, fill = Spec)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.65) +
  geom_text(aes(label = sprintf("%.1f%%", Share_Underpaid * 100)),
            position = position_dodge(width = 0.7), vjust = -0.4, size = 3) +
  geom_hline(yintercept = 0.5, linetype = "dotted", color = "gray50", linewidth = 0.4) +
  scale_fill_manual(values = c("No geographic FE" = ifp_colors$light_blue,
                               "With PUMA FE" = ifp_colors$dark_blue)) +
  scale_y_continuous(labels = percent, limits = c(0, 0.75),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Share of H-1Bs Underpaid Under Different Wage Floor Policies",
    subtitle = "Underpaid = actual wage < Mincer-predicted native-equivalent wage",
    x = "Wage Floor Policy",
    y = "Share of eligible H-1Bs that are underpaid",
    fill = "Mincer Specification",
    caption = paste0("Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS\n",
                     "Wage floors = percentiles of ALL workers in each 6-digit SOC (5-digit, then 3-digit fallback)")
  ) +
  theme_h1b() +
  theme(axis.text.x = element_text(angle = 0, hjust = 0.5, size = 9),
        legend.position = "top")
save_plot(p6, "mincer_06_nprm_scenarios.png", width = 12, height = 7)

# =============================================================================
# 11. Summary
# =============================================================================

cat("\n")
cat("======================================================================\n")
cat("              MINCER ANALYSIS COMPLETE\n")
cat("======================================================================\n\n")

cat("KEY RESULTS (Spec 1: Occupation-specific, national):\n")
cat(sprintf("  H-1B workers analyzed: %s\n", format(spec1$n_valid, big.mark = ",")))
cat(sprintf("  Share earning MORE than predicted native: %.1f%%\n", spec1$share_pos * 100))
cat(sprintf("  Share earning LESS than predicted native: %.1f%%\n", (1 - spec1$share_pos) * 100))
cat(sprintf("  Average wage gap: $%s\n", format(round(spec1$avg_gap), big.mark = ",")))
cat(sprintf("  Median wage gap: $%s\n", format(round(spec1$med_gap), big.mark = ",")))

if (use_fixest) {
  cat(sprintf("\nKEY RESULTS (Spec 2: Occupation-specific + PUMA FE):\n"))
  cat(sprintf("  H-1B workers analyzed: %s\n", format(spec2$n_valid, big.mark = ",")))
  cat(sprintf("  Share earning MORE than predicted native: %.1f%%\n", spec2$share_pos * 100))
  cat(sprintf("  Share earning LESS than predicted native: %.1f%%\n", (1 - spec2$share_pos) * 100))
  cat(sprintf("  Average wage gap: $%s\n", format(round(spec2$avg_gap), big.mark = ",")))
  cat(sprintf("  Median wage gap: $%s\n", format(round(spec2$med_gap), big.mark = ",")))
}

cat("\nOutputs:\n")
cat("  Tables: ", output_tables, "\n")
cat("    - mincer_summary.csv\n")
cat("    - mincer_wage_gaps.csv\n")
cat("    - mincer_occ_diagnostics.csv\n")
cat("    - nprm_wage_floor_analysis.csv\n")
cat("  Figures:", output_figures, "\n")
cat("    - mincer_01_summary_comparison.png\n")
cat("    - mincer_02_gap_distribution.png\n")
cat("    - mincer_03_gap_by_age.png\n")
cat("    - mincer_04_gap_by_wage_level.png\n")
cat("    - mincer_05_occ_diagnostics.png\n")
cat("    - mincer_06_nprm_scenarios.png\n\n")