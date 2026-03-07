# =============================================================================
# DIAGNOSTIC: Why are ~162,000 petitions missing Mincer wages?
# =============================================================================
#
# This script traces data loss through the pipeline to identify why pw_p50
# is NA for approximately 60% of H-1B petitions.
#
# Run this after Scripts 01-05 have completed.
# =============================================================================

# Load configuration
if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
} else {
  stop("Cannot find config.R")
}

library(dplyr)
library(tidyr)

cat("\n")
cat("=============================================================================\n")
cat("DIAGNOSTIC: Missing Mincer Wages\n")
cat("=============================================================================\n\n")

# =============================================================================
# STEP 1: Load data from Script 05 output
# =============================================================================

h1b_file <- file.path(data_processed, "h1b_with_mincer_wages.csv")

if (!file.exists(h1b_file)) {
  stop("Cannot find ", h1b_file, "\n",
       "Please run Script 05 first: source('scripts/05 Apply new PWs to H1B petitions.R')")
}

h1b_22_24 <- read.csv(h1b_file)

cat("Total petitions in dataset:", nrow(h1b_22_24), "\n\n")

# =============================================================================
# STEP 2: Identify petitions with vs. without Mincer wages
# =============================================================================

n_with_wages <- sum(!is.na(h1b_22_24$pw_p50))
n_missing_wages <- sum(is.na(h1b_22_24$pw_p50))

cat("Petitions WITH Mincer wages (pw_p50):   ", n_with_wages,
    sprintf("(%.1f%%)\n", 100 * n_with_wages / nrow(h1b_22_24)))
cat("Petitions WITHOUT Mincer wages (pw_p50):", n_missing_wages,
    sprintf("(%.1f%%)\n\n", 100 * n_missing_wages / nrow(h1b_22_24)))

# =============================================================================
# STEP 3: Check for missing required input fields
# =============================================================================

cat("=============================================================================\n")
cat("REASON 1: Missing Required Input Fields\n")
cat("=============================================================================\n\n")

missing_checks <- list(
  "SOC_CODE" = is.na(h1b_22_24$SOC_CODE),
  "MSA_code" = is.na(h1b_22_24$MSA_code),
  "petition_beneficiary_edu_code" = is.na(h1b_22_24$petition_beneficiary_edu_code),
  "registration_birth_year" = is.na(h1b_22_24$registration_birth_year),
  "registration_lottery_year" = is.na(h1b_22_24$registration_lottery_year)
)

for (field_name in names(missing_checks)) {
  n_missing <- sum(missing_checks[[field_name]])
  cat(sprintf("%-35s: %6d missing (%.1f%%)\n",
              field_name,
              n_missing,
              100 * n_missing / nrow(h1b_22_24)))
}

# Count petitions missing ANY required field
missing_any <- rowSums(do.call(cbind, missing_checks)) > 0
n_missing_any <- sum(missing_any)

cat(sprintf("\n%-35s: %6d (%.1f%%)\n",
            "Missing at least ONE required field",
            n_missing_any,
            100 * n_missing_any / nrow(h1b_22_24)))

# =============================================================================
# STEP 4: Check SOC codes that exist in H-1B but not in OFLC/Mincer models
# =============================================================================

cat("\n")
cat("=============================================================================\n")
cat("REASON 2: SOC Code Not in OFLC Wage Tables or Mincer Models\n")
cat("=============================================================================\n\n")

# Petitions with all required fields present
has_all_fields <- !missing_any

# Among those with all fields, how many still have NA wages?
has_fields_but_no_wage <- has_all_fields & is.na(h1b_22_24$pw_p50)
n_has_fields_but_no_wage <- sum(has_fields_but_no_wage)

cat(sprintf("Petitions WITH all required fields:          %6d (%.1f%%)\n",
            sum(has_all_fields),
            100 * sum(has_all_fields) / nrow(h1b_22_24)))
cat(sprintf("  └─ Of these, have valid Mincer wages:      %6d (%.1f%%)\n",
            sum(has_all_fields & !is.na(h1b_22_24$pw_p50)),
            100 * sum(has_all_fields & !is.na(h1b_22_24$pw_p50)) / sum(has_all_fields)))
cat(sprintf("  └─ Of these, STILL missing Mincer wages:   %6d (%.1f%%)\n\n",
            n_has_fields_but_no_wage,
            100 * n_has_fields_but_no_wage / sum(has_all_fields)))

if (n_has_fields_but_no_wage > 0) {
  # Find which SOC codes are causing failures
  problem_socs <- h1b_22_24 %>%
    filter(has_fields_but_no_wage) %>%
    group_by(SOC_CODE, SOC_TITLE) %>%
    summarise(n = n(), .groups = "drop") %>%
    arrange(desc(n)) %>%
    head(20)

  cat("Top 20 SOC codes with all fields present but NO Mincer wages:\n\n")
  print(problem_socs, n = 20)
}

# =============================================================================
# STEP 5: Geographic coverage - MSAs without OFLC wages
# =============================================================================

cat("\n")
cat("=============================================================================\n")
cat("REASON 3: MSA Code Not in OFLC Wage Tables\n")
cat("=============================================================================\n\n")

if (n_has_fields_but_no_wage > 0) {
  problem_msas <- h1b_22_24 %>%
    filter(has_fields_but_no_wage) %>%
    group_by(MSA_code) %>%
    summarise(n = n(), .groups = "drop") %>%
    arrange(desc(n)) %>%
    head(20)

  cat("Top 20 MSA codes with failed wage lookups:\n\n")
  print(problem_msas, n = 20)
}

# =============================================================================
# STEP 6: Education distribution comparison
# =============================================================================

cat("\n")
cat("=============================================================================\n")
cat("REASON 4: Education Code Issues\n")
cat("=============================================================================\n\n")

edu_comparison <- h1b_22_24 %>%
  mutate(has_wage = !is.na(pw_p50)) %>%
  group_by(petition_beneficiary_edu_code, has_wage) %>%
  summarise(n = n(), .groups = "drop") %>%
  pivot_wider(names_from = has_wage, values_from = n, values_fill = 0) %>%
  rename(with_wage = `TRUE`, without_wage = `FALSE`) %>%
  mutate(
    total = with_wage + without_wage,
    pct_with_wage = 100 * with_wage / total
  ) %>%
  arrange(desc(total))

cat("Education code distribution (with vs. without Mincer wages):\n\n")
print(edu_comparison)

# =============================================================================
# STEP 7: FY year distribution
# =============================================================================

cat("\n")
cat("=============================================================================\n")
cat("REASON 5: Fiscal Year Coverage\n")
cat("=============================================================================\n\n")

fy_comparison <- h1b_22_24 %>%
  mutate(has_wage = !is.na(pw_p50)) %>%
  group_by(registration_lottery_year, has_wage) %>%
  summarise(n = n(), .groups = "drop") %>%
  pivot_wider(names_from = has_wage, values_from = n, values_fill = 0) %>%
  rename(with_wage = `TRUE`, without_wage = `FALSE`) %>%
  mutate(
    total = with_wage + without_wage,
    pct_with_wage = 100 * with_wage / total
  ) %>%
  arrange(registration_lottery_year)

cat("Fiscal year distribution (with vs. without Mincer wages):\n\n")
print(fy_comparison)

# =============================================================================
# STEP 8: Summary recommendations
# =============================================================================

cat("\n")
cat("=============================================================================\n")
cat("SUMMARY & RECOMMENDATIONS\n")
cat("=============================================================================\n\n")

cat("Data Loss Breakdown:\n")
cat(sprintf("  1. Missing required fields:           %6d petitions (%.1f%%)\n",
            n_missing_any, 100 * n_missing_any / nrow(h1b_22_24)))
cat(sprintf("  2. SOC/MSA not in OFLC/Mincer tables: %6d petitions (%.1f%%)\n",
            n_has_fields_but_no_wage,
            100 * n_has_fields_but_no_wage / nrow(h1b_22_24)))
cat(sprintf("  3. Other reasons:                      %6d petitions (%.1f%%)\n\n",
            n_missing_wages - n_missing_any - n_has_fields_but_no_wage,
            100 * (n_missing_wages - n_missing_any - n_has_fields_but_no_wage) / nrow(h1b_22_24)))

cat("Recommendations:\n\n")

if (n_missing_any > 50000) {
  cat("▶ HIGH PRIORITY: Large number of petitions missing required fields.\n")
  cat("  - Check Script 01 (data cleaning): Are SOC codes being matched correctly?\n")
  cat("  - Check Script 02 (geocoding): Are MSA codes being assigned?\n")
  cat("  - Check FOIA data quality: Missing birth years or education codes?\n\n")
}

if (n_has_fields_but_no_wage > 30000) {
  cat("▶ MEDIUM PRIORITY: Many petitions have fields but no OFLC/Mincer match.\n")
  cat("  - Review SOC codes in 'Top 20 SOC codes' table above\n")
  cat("  - Check if these occupations exist in OFLC wage tables\n")
  cat("  - Check if Script 04 estimated models for these occupations\n\n")
}

cat("To investigate further, examine the tables printed above:\n")
cat("  - 'Top 20 SOC codes with failed lookups'\n")
cat("  - 'Top 20 MSA codes with failed lookups'\n")
cat("  - 'Education code distribution'\n")
cat("  - 'Fiscal year distribution'\n\n")

cat("=============================================================================\n")
cat("Diagnostic complete.\n")
cat("=============================================================================\n\n")
