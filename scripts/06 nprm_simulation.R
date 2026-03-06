# =============================================================================
# NPRM Prevailing Wage Simulation (PERCENTILE-BASED)
# =============================================================================
#
# PURPOSE:
#   This script simulates the effect of the proposed NPRM reform to the H-1B
#   prevailing wage system. Under the current system, prevailing wages are
#   anchored to fixed percentiles of the occupational wage distribution:
#   Level I = 17th, Level II = 34th, Level III = 50th, Level IV = 67th.
#
#   The proposed reform raises these thresholds. This script calculates:
#   1. The share of H-1B petitions that would fail to meet the new percentile
#      threshold for their assigned wage level
#   2. Among those that do meet the new threshold, the share that remain
#      underpaid relative to the Mincer-based occupational median (pw_p50)
#
# METHODOLOGY:
#   - Use pre-calculated petition_percentile_combined from Script 05
#   - Four user-provided percentile cutoffs apply to PW_WAGE_LEVEL I, II, III, IV
#   - If petition_percentile_combined >= applicable_threshold → petition qualifies
#   - Among those who qualify, check if petition_annual_pay_clean < pw_p50 → underpaid
#   - pw_p50 (Mincer median) is THE underpayment cutoff for everyone regardless of PW_WAGE_LEVEL
#
# INPUT:
#   data/processed/h1b_with_mincer_wages.csv
#
# =============================================================================

# Load configuration
if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
} else {
  stop("Cannot find config.R. Set your working directory to the project root.")
}

library(dplyr)

# Load H-1B data with Mincer wages
if (!exists("h1b_22_24") || !"pw_p50" %in% names(h1b_22_24)) {
  cat("Loading H-1B data with Mincer wages...\n")
  input_file <- file.path(data_processed, "h1b_with_mincer_wages.csv")

  if (!file.exists(input_file)) {
    stop("Data file not found: ", input_file,
         "\nRun Scripts 04-05 first to generate Mincer wages.")
  }

  h1b_22_24 <- read.csv(input_file)
  cat("Loaded:", input_file, "\n\n")
}

# =============================================================================
# USER-CONFIGURABLE PARAMETERS
# =============================================================================
#
# Set the proposed percentile thresholds for each of the four wage levels.
#
# STATUS QUO SYSTEM (for reference):
#   pw_level_I_threshold   <- 17
#   pw_level_II_threshold  <- 34
#   pw_level_III_threshold <- 50
#   pw_level_IV_threshold  <- 67
#
# 2021 RULE (proposed DOL reform):

pw_level_I_threshold   <- 35
pw_level_II_threshold  <- 53
pw_level_III_threshold <- 72
pw_level_IV_threshold  <- 90

# =============================================================================
# STEP 1: DETERMINE QUALIFICATION UNDER PROPOSED SYSTEM
# =============================================================================
#
# Use petition_percentile_combined (calculated in Script 05) to determine
# whether each petition meets the new percentile threshold for their assigned
# wage level.
#
# =============================================================================

h1b_sim <- h1b_22_24 %>%
  filter(!is.na(pw_p50)) %>%  # Only use petitions with valid Mincer wages
  mutate(
    # Assign applicable threshold based on PW_WAGE_LEVEL
    applicable_threshold = case_when(
      PW_WAGE_LEVEL == "I"   ~ pw_level_I_threshold,
      PW_WAGE_LEVEL == "II"  ~ pw_level_II_threshold,
      PW_WAGE_LEVEL == "III" ~ pw_level_III_threshold,
      PW_WAGE_LEVEL == "IV"  ~ pw_level_IV_threshold,
      TRUE ~ NA_real_
    ),

    # Does petition qualify under proposed system?
    # (i.e., does their percentile meet the new threshold for their level?)
    qualifies = !is.na(applicable_threshold) &
                !is.na(petition_percentile_combined) &
                petition_percentile_combined >= applicable_threshold,

    # Is petition underpaid relative to Mincer median?
    # This applies to everyone, regardless of PW_WAGE_LEVEL
    underpaid_vs_mincer = !is.na(petition_annual_pay_clean) &
                          !is.na(pw_p50) &
                          petition_annual_pay_clean < pw_p50
  )

cat("=============================================================\n")
cat("NPRM Prevailing Wage Simulation (PERCENTILE-BASED)\n")
cat("=============================================================\n")
cat("Proposed percentile thresholds by wage level:\n")
cat("  Level I:   >= ", pw_level_I_threshold,   "th percentile\n", sep = "")
cat("  Level II:  >= ", pw_level_II_threshold,  "th percentile\n", sep = "")
cat("  Level III: >= ", pw_level_III_threshold, "th percentile\n", sep = "")
cat("  Level IV:  >= ", pw_level_IV_threshold,  "th percentile\n", sep = "")
cat("-------------------------------------------------------------\n\n")

cat("Total petitions in dataset:", nrow(h1b_22_24), "\n")
cat("Petitions with valid Mincer wages (pw_p50):", nrow(h1b_sim), "\n")
cat("Petitions with valid PW_WAGE_LEVEL:",
    sum(!is.na(h1b_sim$PW_WAGE_LEVEL)), "\n")
cat("Petitions with valid percentile (petition_percentile_combined):",
    sum(!is.na(h1b_sim$petition_percentile_combined)), "\n\n")

# =============================================================================
# STEP 2: FILTER TO PETITIONS THAT QUALIFY UNDER PROPOSED SYSTEM
# =============================================================================

# Petitions that qualify (meet the new percentile threshold)
h1b_qualified <- h1b_sim %>%
  filter(qualifies == TRUE)

# Petitions that don't qualify
h1b_not_qualified <- h1b_sim %>%
  filter(qualifies == FALSE | is.na(qualifies))

n_evaluable <- sum(!is.na(h1b_sim$qualifies))
n_qualified <- nrow(h1b_qualified)
n_not_qualified <- nrow(h1b_not_qualified)

cat("-------------------------------------------------------------\n")
cat("Petitions evaluable (have Mincer wages + percentile):", n_evaluable, "\n")
cat("Petitions that QUALIFY under proposed system:", n_qualified,
    sprintf("(%.1f%% of evaluable)\n", 100 * n_qualified / n_evaluable))
cat("Petitions that DO NOT QUALIFY:", n_not_qualified,
    sprintf("(%.1f%% of evaluable)\n", 100 * n_not_qualified / n_evaluable))
cat("-------------------------------------------------------------\n\n")

# =============================================================================
# STEP 3: CALCULATE UNDERPAYMENT AMONG PETITIONS THAT QUALIFY
# =============================================================================
#
# Among petitions that qualify under the proposed system, how many are still
# underpaid relative to the Mincer median (pw_p50)?
#
# =============================================================================

n_qualified_evaluable <- sum(!is.na(h1b_qualified$underpaid_vs_mincer))
n_underpaid <- sum(h1b_qualified$underpaid_vs_mincer, na.rm = TRUE)
n_adequately_paid <- n_qualified_evaluable - n_underpaid
share_underpaid <- n_underpaid / n_qualified_evaluable

cat("=============================================================\n")
cat("UNDERPAYMENT RESULTS\n")
cat("=============================================================\n")
cat("Among petitions qualifying under the proposed system:\n\n")
cat("  Total petitions evaluated:    ", n_qualified_evaluable, "\n")
cat("  Paid below Mincer median (pw_p50):     ", n_underpaid,
    sprintf("(%.1f%%)\n", 100 * share_underpaid))
cat("  Paid at or above Mincer median:", n_adequately_paid,
    sprintf("(%.1f%%)\n", 100 * (1 - share_underpaid)))
cat("-------------------------------------------------------------\n\n")

# =============================================================================
# STEP 4: BREAKDOWN BY WAGE LEVEL
# =============================================================================

cat("Qualification and underpayment by assigned wage level:\n\n")

breakdown_by_level <- h1b_sim %>%
  filter(!is.na(qualifies)) %>%
  group_by(PW_WAGE_LEVEL) %>%
  summarise(
    n_petitions = n(),
    n_qualified = sum(qualifies, na.rm = TRUE),
    share_qualified = mean(qualifies, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(PW_WAGE_LEVEL) %>%
  mutate(
    threshold = case_when(
      PW_WAGE_LEVEL == "I"   ~ pw_level_I_threshold,
      PW_WAGE_LEVEL == "II"  ~ pw_level_II_threshold,
      PW_WAGE_LEVEL == "III" ~ pw_level_III_threshold,
      PW_WAGE_LEVEL == "IV"  ~ pw_level_IV_threshold
    ),
    share_qualified_pct = paste0(round(100 * share_qualified, 1), "%")
  ) %>%
  select(PW_WAGE_LEVEL, threshold, n_petitions, n_qualified, share_qualified_pct)

cat("Qualification rates:\n")
print(breakdown_by_level)
cat("\n")

# Among those who qualify, how many are underpaid?
underpayment_by_level <- h1b_qualified %>%
  filter(!is.na(underpaid_vs_mincer)) %>%
  group_by(PW_WAGE_LEVEL) %>%
  summarise(
    n_petitions = n(),
    n_underpaid = sum(underpaid_vs_mincer, na.rm = TRUE),
    share_underpaid = mean(underpaid_vs_mincer, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(PW_WAGE_LEVEL) %>%
  mutate(
    share_underpaid_pct = paste0(round(100 * share_underpaid, 1), "%")
  ) %>%
  select(PW_WAGE_LEVEL, n_petitions, n_underpaid, share_underpaid_pct)

cat("Underpayment among qualified petitions:\n")
print(underpayment_by_level)
cat("\n")

# =============================================================================
# STEP 5: SUMMARY TABLE FOR REPORTING
# =============================================================================

cat("=============================================================\n")
cat("SUMMARY FOR REPORTING\n")
cat("=============================================================\n")
cat(sprintf(
  "Under the proposed system (Level I >= %dth pct, Level II >= %dth pct,\n",
  pw_level_I_threshold, pw_level_II_threshold
))
cat(sprintf(
  "Level III >= %dth pct, Level IV >= %dth pct):\n\n",
  pw_level_III_threshold, pw_level_IV_threshold
))
cat(sprintf(
  "  %.1f%% of evaluable petitions do not meet the new percentile threshold\n",
  100 * n_not_qualified / n_evaluable
))
cat(sprintf(
  "  Among petitions that qualify, %.1f%% remain underpaid\n",
  100 * share_underpaid
))
cat(sprintf(
  "  relative to the Mincer median (pw_p50) for their specific\n"
))
cat(sprintf(
  "  education, experience, occupation, and metro area.\n"
))
cat("=============================================================\n")
