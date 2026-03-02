# =============================================================================
# NPRM Prevailing Wage Simulation
# =============================================================================
#
# PURPOSE:
#   This script simulates the effect of a proposed reform to the H-1B
#   prevailing wage system. Under the current system, prevailing wages are
#   anchored to fixed percentiles of the occupational wage distribution:
#   Level I = 17th, Level II = 34th, Level III = 50th, Level IV = 67th.
#
#   The proposed reform raises these thresholds, requiring employers to pay
#   higher wages relative to the occupation's wage distribution. This script
#   calculates the share of H-1B petitions that would still be underpaid
#   (i.e. paid below the Mincer-based occupational median for their specific
#   education and experience profile) after the proposed thresholds take effect.
#
# LOGIC:
#   Step 1: The user sets four new percentile thresholds — one per wage level.
#   Step 2: We filter to petitions that would be "in scope" under the proposed
#           rules: those whose current pay already meets the new threshold for
#           their assigned wage level. Petitions below the threshold are already
#           underpaid relative to the new floor and are excluded from the
#           "surviving" pool used to calculate underpayment.
#
#           RATIONALE FOR FILTERING: The proposed rules change the minimum
#           prevailing wage, not the observed wages themselves. Petitions below
#           the new threshold would presumably need to be repriced or would not
#           be filed; we focus on those that clear the new floor.
#
#   Step 3: Among petitions that clear the new threshold, we calculate the share
#           that are still underpaid relative to their Mincer-based wage — i.e.
#           paid below pw_p50, the occupation-area-education-experience median.
#
# INPUT:
#   data/processed/h1b_with_mincer_wages.csv (or h1b_22_24 object in memory from Script 05)
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

# Load or create h1b_22_24 dataset
if (!exists("h1b_22_24") || !"pw_p50" %in% names(h1b_22_24)) {
  cat("Loading H-1B data with Mincer wages...\n")
  input_file <- file.path(data_processed, "h1b_with_mincer_wages.csv")

  if (!file.exists(input_file)) {
    cat("Data file not found. Running Scripts 04 and 05 first...\n\n")
    source(file.path("scripts", "04 Calculate new prevailing wages.R"), local = FALSE)
    source(file.path("scripts", "05 Apply new PWs to H1B petitions.R"), local = FALSE)
    cat("\nScripts 04-05 complete. Continuing with Script 06...\n\n")
  } else {
    h1b_22_24 <- read.csv(input_file)
    cat("Loaded:", input_file, "\n\n")
  }
}

# =============================================================================
# USER-CONFIGURABLE PARAMETERS
# =============================================================================
#
# Set the proposed percentile thresholds for each of the four wage levels.
# A petition assigned Level I must have a wage at or above the pw_level_I_threshold
# percentile of its occupation's wage distribution to clear the new floor.
#
# CURRENT SYSTEM (for reference):
#   pw_level_I_threshold   <- 17
#   pw_level_II_threshold  <- 34
#   pw_level_III_threshold <- 50
#   pw_level_IV_threshold  <- 67
#
# PROPOSED SYSTEM (User-set percentiles):

pw_level_I_threshold   <- 34
pw_level_II_threshold  <- 52
pw_level_III_threshold <- 70
pw_level_IV_threshold  <- 88

# =============================================================================
# STEP 1: ASSIGN APPLICABLE THRESHOLD TO EACH PETITION
# =============================================================================
#
# Each petition is assigned a prevailing wage level (I through IV) by DOL
# based on the employer's description of the job. We map each level to the
# user-specified percentile threshold above.
#
# Petitions with missing PW_WAGE_LEVEL or petition_percentile_combined are
# excluded from the analysis — they cannot be evaluated against the threshold.
#
# =============================================================================

h1b_sim <- h1b_22_24 %>%
  mutate(
    applicable_threshold = case_when(
      PW_WAGE_LEVEL == "I"   ~ pw_level_I_threshold,
      PW_WAGE_LEVEL == "II"  ~ pw_level_II_threshold,
      PW_WAGE_LEVEL == "III" ~ pw_level_III_threshold,
      PW_WAGE_LEVEL == "IV"  ~ pw_level_IV_threshold,
      TRUE ~ NA_real_
    )
  )

cat("=============================================================\n")
cat("NPRM Prevailing Wage Simulation\n")
cat("=============================================================\n")
cat("Proposed thresholds by wage level:\n")
cat("  Level I:   >= ", pw_level_I_threshold,   "th percentile\n", sep = "")
cat("  Level II:  >= ", pw_level_II_threshold,  "th percentile\n", sep = "")
cat("  Level III: >= ", pw_level_III_threshold, "th percentile\n", sep = "")
cat("  Level IV:  >= ", pw_level_IV_threshold,  "th percentile\n", sep = "")
cat("-------------------------------------------------------------\n\n")

cat("Total petitions in dataset:", nrow(h1b_sim), "\n")
cat("Petitions with valid PW_WAGE_LEVEL:",
    sum(!is.na(h1b_sim$applicable_threshold)), "\n")
cat("Petitions with valid petition_percentile_combined:",
    sum(!is.na(h1b_sim$petition_percentile_combined)), "\n\n")

# =============================================================================
# STEP 2: FILTER TO PETITIONS THAT CLEAR THE NEW THRESHOLD
# =============================================================================
#
# Under the proposed rules, only petitions whose current pay is at or above
# the new percentile floor for their assigned wage level would satisfy the
# prevailing wage requirement. We restrict the analysis to this "surviving"
# pool — petitions that clear the new floor.
#
# Petitions that do not clear the new floor are flagged separately so we can
# report their share of the total.
#
# =============================================================================

h1b_above_threshold <- h1b_sim %>%
  filter(
    !is.na(applicable_threshold),
    !is.na(petition_percentile_combined),
    petition_percentile_combined >= applicable_threshold
  )

h1b_below_threshold <- h1b_sim %>%
  filter(
    !is.na(applicable_threshold),
    !is.na(petition_percentile_combined),
    petition_percentile_combined < applicable_threshold
  )

n_evaluable   <- nrow(h1b_above_threshold) + nrow(h1b_below_threshold)
n_above       <- nrow(h1b_above_threshold)
n_below       <- nrow(h1b_below_threshold)

cat("-------------------------------------------------------------\n")
cat("Petitions evaluable (valid level + valid percentile):", n_evaluable, "\n")
cat("Petitions that CLEAR the new threshold:", n_above,
    sprintf("(%.1f%% of evaluable)\n", 100 * n_above / n_evaluable))
cat("Petitions BELOW the new threshold:", n_below,
    sprintf("(%.1f%% of evaluable)\n", 100 * n_below / n_evaluable))
cat("-------------------------------------------------------------\n\n")

# =============================================================================
# STEP 3: CALCULATE UNDERPAYMENT AMONG PETITIONS THAT CLEAR THE THRESHOLD
# =============================================================================
#
# Among petitions that clear the new wage floor, we ask: what share are still
# paid less than the Mincer-based occupational median (pw_p50) for their
# specific education level, years of experience, occupation, and metro area?
#
# pw_p50 is derived from the Mincer estimation script and represents the
# median wage for a worker with the same qualifications in the same occupation
# and area. A petition is "underpaid" if petition_annual_pay_clean < pw_p50.
#
# We restrict to petitions with non-missing pw_p50 for this calculation.
#
# =============================================================================

h1b_underpayment <- h1b_above_threshold %>%
  filter(!is.na(pw_p50))

n_with_mincer_wage <- nrow(h1b_underpayment)
n_underpaid        <- sum(h1b_underpayment$petition_annual_pay_clean < h1b_underpayment$pw_p50)
n_adequately_paid  <- n_with_mincer_wage - n_underpaid
share_underpaid    <- n_underpaid / n_with_mincer_wage

cat("=============================================================\n")
cat("UNDERPAYMENT RESULTS\n")
cat("=============================================================\n")
cat("Among petitions clearing the new threshold with valid Mincer wages:\n\n")
cat("  Total petitions evaluated:    ", n_with_mincer_wage, "\n")
cat("  Paid below Mincer median:     ", n_underpaid,
    sprintf("(%.1f%%)\n", 100 * share_underpaid))
cat("  Paid at or above Mincer median:", n_adequately_paid,
    sprintf("(%.1f%%)\n", 100 * (1 - share_underpaid)))
cat("-------------------------------------------------------------\n\n")

# =============================================================================
# STEP 4: BREAKDOWN BY WAGE LEVEL
# =============================================================================
#
# Underpayment rates often differ substantially across wage levels. Level I
# petitions (entry-level per the employer's description) may have very
# different underpayment rates than Level IV (fully competent) petitions.
#
# =============================================================================

cat("Underpayment by assigned wage level:\n\n")

underpayment_by_level <- h1b_underpayment %>%
  group_by(PW_WAGE_LEVEL) %>%
  summarise(
    n_petitions    = n(),
    n_underpaid    = sum(petition_annual_pay_clean < pw_p50),
    share_underpaid = mean(petition_annual_pay_clean < pw_p50),
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
    share_underpaid_pct = paste0(round(100 * share_underpaid, 1), "%")
  ) %>%
  select(PW_WAGE_LEVEL, threshold, n_petitions, n_underpaid, share_underpaid_pct)

print(underpayment_by_level)
cat("\n")

# =============================================================================
# STEP 6: SUMMARY TABLE FOR REPORTING
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
  "  %.1f%% of evaluable petitions fall below the new wage floor\n",
  100 * n_below / n_evaluable
))
cat(sprintf(
  "  Among petitions clearing the new floor, %.1f%% remain underpaid\n",
  100 * share_underpaid
))
cat(sprintf(
  "  relative to the Mincer-estimated occupational median for their\n"
))
cat(sprintf(
  "  specific education, experience, occupation, and metro area.\n"
))
cat("=============================================================\n")