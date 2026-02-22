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
# Fit separately per 6-digit SOC occupation (fallback to 3-digit, 2-digit,
# then pooled if sample too small).
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
# 1. Setup and Configuration
# =============================================================================

if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
} else {
  stop("Cannot find config.R. Please run from project root or scripts/ directory")
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
occ3_counts <- natives_df %>% count(OCC3, name = "n_natives_3")
occ2_counts <- natives_df %>% count(OCC2, name = "n_natives_2")

# Determine which level each H-1B gets matched at
h1b_df <- h1b_df %>%
  left_join(occ6_counts, by = "OCCSOC") %>%
  left_join(occ3_counts, by = "OCC3") %>%
  left_join(occ2_counts, by = "OCC2") %>%
  mutate(
    n_natives_6 = replace_na(n_natives_6, 0),
    n_natives_3 = replace_na(n_natives_3, 0),
    n_natives_2 = replace_na(n_natives_2, 0),
    match_level = case_when(
      n_natives_6 >= MIN_NATIVES ~ "6-digit",
      n_natives_3 >= MIN_NATIVES ~ "3-digit",
      n_natives_2 >= MIN_NATIVES ~ "2-digit",
      TRUE ~ "pooled"
    ),
    match_occ = case_when(
      match_level == "6-digit" ~ OCCSOC,
      match_level == "3-digit" ~ OCC3,
      match_level == "2-digit" ~ OCC2,
      TRUE ~ "ALL"
    )
  )

cat("H-1B match levels:\n")
cat("  6-digit SOC:", sum(h1b_df$match_level == "6-digit"), "\n")
cat("  3-digit SOC:", sum(h1b_df$match_level == "3-digit"), "\n")
cat("  2-digit SOC:", sum(h1b_df$match_level == "2-digit"), "\n")
cat("  Pooled:     ", sum(h1b_df$match_level == "pooled"), "\n\n")

# --- Helper: fit Mincer and predict ---
fit_and_predict <- function(native_subset, h1b_subset) {
  # Murphy-Welch quartic with education dummies (no year FE -- enables future prediction)
  n_educ_levels <- n_distinct(native_subset$EDUCD_f)

  # Build formula dynamically based on available variation
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
    error = function(e) {
      # If prediction fails (e.g., new factor levels), return NA
      rep(NA_real_, nrow(h1b_subset))
    }
  )
}

# --- Spec 1: National (no PUMA FE) ---
cat("=== Specification 1: National (by occupation) ===\n")

# Get unique occupation groups to fit
occ_groups_6 <- unique(h1b_df$OCCSOC[h1b_df$match_level == "6-digit"])
occ_groups_3 <- unique(h1b_df$OCC3[h1b_df$match_level == "3-digit"])
occ_groups_2 <- unique(h1b_df$OCC2[h1b_df$match_level == "2-digit"])

h1b_df$predicted_ln_wage_1 <- NA_real_

# Fit at 6-digit level
cat(sprintf("  Fitting %d 6-digit occupation models...\n", length(occ_groups_6)))
pb_total <- length(occ_groups_6)
for (i in seq_along(occ_groups_6)) {
  occ <- occ_groups_6[i]
  idx_h1b <- which(h1b_df$OCCSOC == occ & h1b_df$match_level == "6-digit")
  if (length(idx_h1b) == 0) next

  native_sub <- natives_df %>% filter(OCCSOC == occ)
  h1b_sub <- h1b_df[idx_h1b, ]
  h1b_df$predicted_ln_wage_1[idx_h1b] <- fit_and_predict(native_sub, h1b_sub)

  if (i %% 50 == 0 || i == pb_total) {
    cat(sprintf("    [%d/%d] occupations fitted\r", i, pb_total))
  }
}
cat("\n")

# Fit at 3-digit level
cat(sprintf("  Fitting %d 3-digit occupation models...\n", length(occ_groups_3)))
for (occ in occ_groups_3) {
  idx_h1b <- which(h1b_df$OCC3 == occ & h1b_df$match_level == "3-digit")
  if (length(idx_h1b) == 0) next

  native_sub <- natives_df %>% filter(OCC3 == occ)
  h1b_sub <- h1b_df[idx_h1b, ]
  h1b_df$predicted_ln_wage_1[idx_h1b] <- fit_and_predict(native_sub, h1b_sub)
}

# Fit at 2-digit level
cat(sprintf("  Fitting %d 2-digit occupation models...\n", length(occ_groups_2)))
for (occ in occ_groups_2) {
  idx_h1b <- which(h1b_df$OCC2 == occ & h1b_df$match_level == "2-digit")
  if (length(idx_h1b) == 0) next

  native_sub <- natives_df %>% filter(OCC2 == occ)
  h1b_sub <- h1b_df[idx_h1b, ]
  h1b_df$predicted_ln_wage_1[idx_h1b] <- fit_and_predict(native_sub, h1b_sub)
}

# Fit pooled model for remainder
pooled_idx <- which(h1b_df$match_level == "pooled")
if (length(pooled_idx) > 0) {
  cat(sprintf("  Fitting pooled model for %d remaining H-1Bs...\n", length(pooled_idx)))
  h1b_df$predicted_ln_wage_1[pooled_idx] <- fit_and_predict(natives_df, h1b_df[pooled_idx, ])
}

# Compute gaps for Spec 1
h1b_df <- h1b_df %>%
  mutate(
    predicted_wage_1 = exp(predicted_ln_wage_1),
    gap_1 = INCWAGE - predicted_wage_1,
    log_gap_1 = ln_wage - predicted_ln_wage_1
  )

n_valid_1 <- sum(!is.na(h1b_df$gap_1))
share_pos_1 <- mean(h1b_df$gap_1 > 0, na.rm = TRUE)
avg_gap_1 <- mean(h1b_df$gap_1, na.rm = TRUE)
med_gap_1 <- median(h1b_df$gap_1, na.rm = TRUE)

cat(sprintf("\nSpec 1 Results (National, by occupation):\n"))
cat(sprintf("  Valid predictions: %s / %s (%.1f%%)\n",
            format(n_valid_1, big.mark = ","),
            format(nrow(h1b_df), big.mark = ","),
            n_valid_1 / nrow(h1b_df) * 100))
cat(sprintf("  Share with positive gap: %.1f%%\n", share_pos_1 * 100))
cat(sprintf("  Average gap: $%s\n", format(round(avg_gap_1), big.mark = ",")))
cat(sprintf("  Median gap: $%s\n", format(round(med_gap_1), big.mark = ",")))

# --- Spec 2: With PUMA FE (using fixest) ---
if (use_fixest) {
  cat("\n=== Specification 2: With PUMA FE (by occupation) ===\n")

  h1b_df$predicted_ln_wage_2 <- NA_real_

  # Helper for fixest-based fitting with PUMA FE
  fit_and_predict_puma <- function(native_subset, h1b_subset) {
    n_educ_levels <- n_distinct(native_subset$EDUCD_f)
    n_puma_levels <- n_distinct(native_subset$PUMA)

    # Need enough PUMAs to justify FE; otherwise fall back to no-PUMA
    if (n_puma_levels < 3 || nrow(native_subset) < 100) {
      return(fit_and_predict(native_subset, h1b_subset))
    }

    # Build fixest formula: covariates | fixed_effects (no year FE -- enables future prediction)
    rhs_parts <- c("X", "X2", "X3", "X4")
    if (n_educ_levels > 1) rhs_parts <- c(rhs_parts, "EDUCD_f")

    fe_parts <- "PUMA"

    fml <- as.formula(paste("ln_wage ~", paste(rhs_parts, collapse = " + "),
                            "|", paste(fe_parts, collapse = " + ")))

    fit <- tryCatch(
      feols(fml, data = native_subset, weights = ~PERWT, notes = FALSE, warn = FALSE),
      error = function(e) NULL
    )

    if (is.null(fit)) return(fit_and_predict(native_subset, h1b_subset))

    tryCatch(
      predict(fit, newdata = h1b_subset),
      error = function(e) fit_and_predict(native_subset, h1b_subset)
    )
  }

  # Fit at 6-digit level
  cat(sprintf("  Fitting %d 6-digit occupation models with PUMA FE...\n", length(occ_groups_6)))
  for (i in seq_along(occ_groups_6)) {
    occ <- occ_groups_6[i]
    idx_h1b <- which(h1b_df$OCCSOC == occ & h1b_df$match_level == "6-digit")
    if (length(idx_h1b) == 0) next

    native_sub <- natives_df %>% filter(OCCSOC == occ)
    h1b_sub <- h1b_df[idx_h1b, ]
    h1b_df$predicted_ln_wage_2[idx_h1b] <- fit_and_predict_puma(native_sub, h1b_sub)

    if (i %% 50 == 0 || i == length(occ_groups_6)) {
      cat(sprintf("    [%d/%d] occupations fitted\r", i, length(occ_groups_6)))
    }
  }
  cat("\n")

  # Fit at 3-digit level
  cat(sprintf("  Fitting %d 3-digit models with PUMA FE...\n", length(occ_groups_3)))
  for (occ in occ_groups_3) {
    idx_h1b <- which(h1b_df$OCC3 == occ & h1b_df$match_level == "3-digit")
    if (length(idx_h1b) == 0) next

    native_sub <- natives_df %>% filter(OCC3 == occ)
    h1b_sub <- h1b_df[idx_h1b, ]
    h1b_df$predicted_ln_wage_2[idx_h1b] <- fit_and_predict_puma(native_sub, h1b_sub)
  }

  # Fit at 2-digit level
  cat(sprintf("  Fitting %d 2-digit models with PUMA FE...\n", length(occ_groups_2)))
  for (occ in occ_groups_2) {
    idx_h1b <- which(h1b_df$OCC2 == occ & h1b_df$match_level == "2-digit")
    if (length(idx_h1b) == 0) next

    native_sub <- natives_df %>% filter(OCC2 == occ)
    h1b_sub <- h1b_df[idx_h1b, ]
    h1b_df$predicted_ln_wage_2[idx_h1b] <- fit_and_predict_puma(native_sub, h1b_sub)
  }

  # Pooled with PUMA FE
  if (length(pooled_idx) > 0) {
    cat(sprintf("  Fitting pooled model with PUMA FE for %d H-1Bs...\n", length(pooled_idx)))
    h1b_df$predicted_ln_wage_2[pooled_idx] <- fit_and_predict_puma(natives_df, h1b_df[pooled_idx, ])
  }

  # Compute gaps for Spec 2
  h1b_df <- h1b_df %>%
    mutate(
      predicted_wage_2 = exp(predicted_ln_wage_2),
      gap_2 = INCWAGE - predicted_wage_2,
      log_gap_2 = ln_wage - predicted_ln_wage_2
    )

  n_valid_2 <- sum(!is.na(h1b_df$gap_2))
  share_pos_2 <- mean(h1b_df$gap_2 > 0, na.rm = TRUE)
  avg_gap_2 <- mean(h1b_df$gap_2, na.rm = TRUE)
  med_gap_2 <- median(h1b_df$gap_2, na.rm = TRUE)

  cat(sprintf("\nSpec 2 Results (With PUMA FE, by occupation):\n"))
  cat(sprintf("  Valid predictions: %s / %s (%.1f%%)\n",
              format(n_valid_2, big.mark = ","),
              format(nrow(h1b_df), big.mark = ","),
              n_valid_2 / nrow(h1b_df) * 100))
  cat(sprintf("  Share with positive gap: %.1f%%\n", share_pos_2 * 100))
  cat(sprintf("  Average gap: $%s\n", format(round(avg_gap_2), big.mark = ",")))
  cat(sprintf("  Median gap: $%s\n", format(round(med_gap_2), big.mark = ",")))
}

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
    Specification = "Mincer: Occupation-specific (national)",
    Sample_Size = n_valid_1,
    Share_Positive = share_pos_1,
    Avg_Gap = avg_gap_1,
    Median_Gap = med_gap_1
  )
)

if (use_fixest) {
  summary_rows[[2]] <- tibble(
    Specification = "Mincer: Occupation-specific + PUMA FE",
    Sample_Size = n_valid_2,
    Share_Positive = share_pos_2,
    Avg_Gap = avg_gap_2,
    Median_Gap = med_gap_2
  )
}

summary_table <- bind_rows(summary_rows)

# Also add breakdowns by match level for Spec 1
match_summary <- h1b_df %>%
  filter(!is.na(gap_1)) %>%
  group_by(match_level) %>%
  summarise(
    N = n(),
    Share_Positive = mean(gap_1 > 0),
    Avg_Gap = mean(gap_1),
    Median_Gap = median(gap_1),
    .groups = "drop"
  ) %>%
  arrange(factor(match_level, levels = c("6-digit", "3-digit", "2-digit", "pooled")))

cat("\nSpec 1 by match level:\n")
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

export_cols <- c("YEAR", "AGE", "OCCSOC", "OCC2", "OCC3", "EDUCD_int",
                 "S", "X", "INCWAGE", "h1b_dependent", "wage_level",
                 "match_level", "match_occ",
                 "predicted_wage_1", "gap_1", "log_gap_1")

if (use_fixest) {
  export_cols <- c(export_cols, "predicted_wage_2", "gap_2", "log_gap_2")
}

gaps_export <- h1b_df %>% select(all_of(export_cols))

write.csv(gaps_export, file.path(output_tables, "mincer_wage_gaps.csv"), row.names = FALSE)
cat(sprintf("Saved: output/tables/mincer_wage_gaps.csv (%s rows)\n",
            format(nrow(gaps_export), big.mark = ",")))

# =============================================================================
# 8. Figures
# =============================================================================

cat("\n=== Generating Figures ===\n")

# Use Spec 1 as primary (full coverage), note Spec 2 where available
h1b_plot <- h1b_df %>% filter(!is.na(gap_1))

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
      Control = c("Occ-Specific", if (use_fixest) "Occ-Specific + PUMA" else NULL),
      Share_Positive = c(share_pos_1, if (use_fixest) share_pos_2 else NULL)
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
p2 <- ggplot(h1b_plot, aes(x = gap_1 / 1000)) +
  geom_histogram(binwidth = 5, fill = ifp_colors$dark_blue, color = "white",
                 alpha = 0.8, boundary = 0) +
  geom_vline(xintercept = 0, linetype = "dashed", color = ifp_colors$red, linewidth = 0.8) +
  annotate("text", x = med_gap_1 / 1000, y = Inf, vjust = 2,
           label = sprintf("Median: $%sk", round(med_gap_1 / 1000, 1)),
           color = ifp_colors$rich_black, size = 3.5) +
  scale_x_continuous(limits = c(-150, 200), labels = function(x) paste0("$", x, "k")) +
  labs(
    title = "Distribution of Individual H-1B Wage Gaps (Mincer Prediction)",
    subtitle = sprintf("%.1f%% of H-1Bs earn more than their predicted native-equivalent wage",
                        share_pos_1 * 100),
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
    share_positive = mean(gap_1 > 0),
    avg_gap = mean(gap_1),
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
    share_positive = mean(gap_1 > 0),
    avg_gap = mean(gap_1),
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
# 9. Summary
# =============================================================================

cat("\n")
cat("======================================================================\n")
cat("              MINCER ANALYSIS COMPLETE\n")
cat("======================================================================\n\n")

cat("KEY RESULTS (Spec 1: Occupation-specific, national):\n")
cat(sprintf("  H-1B workers analyzed: %s\n", format(n_valid_1, big.mark = ",")))
cat(sprintf("  Share earning MORE than predicted native: %.1f%%\n", share_pos_1 * 100))
cat(sprintf("  Share earning LESS than predicted native: %.1f%%\n", (1 - share_pos_1) * 100))
cat(sprintf("  Average wage gap: $%s\n", format(round(avg_gap_1), big.mark = ",")))
cat(sprintf("  Median wage gap: $%s\n", format(round(med_gap_1), big.mark = ",")))

if (use_fixest) {
  cat(sprintf("\nKEY RESULTS (Spec 2: Occupation-specific + PUMA FE):\n"))
  cat(sprintf("  H-1B workers analyzed: %s\n", format(n_valid_2, big.mark = ",")))
  cat(sprintf("  Share earning MORE than predicted native: %.1f%%\n", share_pos_2 * 100))
  cat(sprintf("  Share earning LESS than predicted native: %.1f%%\n", (1 - share_pos_2) * 100))
  cat(sprintf("  Average wage gap: $%s\n", format(round(avg_gap_2), big.mark = ",")))
  cat(sprintf("  Median wage gap: $%s\n", format(round(med_gap_2), big.mark = ",")))
}

cat("\nOutputs:\n")
cat("  Tables: ", output_tables, "\n")
cat("    - mincer_summary.csv\n")
cat("    - mincer_wage_gaps.csv\n")
cat("    - mincer_occ_diagnostics.csv\n")
cat("  Figures:", output_figures, "\n")
cat("    - mincer_01_summary_comparison.png\n")
cat("    - mincer_02_gap_distribution.png\n")
cat("    - mincer_03_gap_by_age.png\n")
cat("    - mincer_04_gap_by_wage_level.png\n")
cat("    - mincer_05_occ_diagnostics.png\n\n")
