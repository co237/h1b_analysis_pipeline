################################################################################
# Script 09: Calculate Expected Lifetime Earnings for H-1B Petitions
#
# Purpose: Generate NPV multipliers from ACS data and tag H-1B petitions with
#          expected lifetime earnings based on age and current salary
#
# Inputs:  - data/raw/usa_00076.dat.gz (IPUMS ACS microdata)
#          - data/raw/usa_00076.xml (IPUMS DDI)
#          - data/processed/h1b_with_mincer_wages.csv
#
# Outputs: - data/intermediate/acs_npv_multipliers.csv (age-specific multipliers)
#          - data/processed/h1b_with_lifetime_earnings.csv (H-1B data with NPV)
#
# Author: Connor O'Brien / Institute for Progress
# Date: March 2026
################################################################################

# Load libraries ---------------------------------------------------------------
library(ipumsr)
library(dplyr)
library(purrr)
library(slider)
library(readr)

cat("=== Step 1: Calculate NPV Multipliers from ACS Data ===\n")

# Load IPUMS ACS microdata -----------------------------------------------------
cat("Loading IPUMS ACS microdata (usa_00076)...\n")
ddi_acs <- read_ipums_ddi("data/raw/usa_00076.xml")
acs <- read_ipums_micro(ddi_acs)

cat(sprintf("Loaded %s ACS observations\n", format(nrow(acs), big.mark = ",")))

# Calculate age-wage profiles --------------------------------------------------
cat("\nCalculating age-wage profiles...\n")

# Filter to college-educated workers with positive wages (matching EIG methodology)
# - EDUCD >= 101: Bachelor's degree or higher
# - EMPSTAT == 1: Employed
# - INCWAGE > 0: Positive wage income
acs_filtered <- acs %>%
  filter(
    EDUCD >= 101,        # Bachelor's degree or higher
    EMPSTAT == 1,        # Employed
    INCWAGE > 0,         # Positive wage income
    AGE <= 71            # Working ages
  ) %>%
  mutate(AGE = ifelse(AGE < 22, 22, AGE))  # Bottom-code age at 22

cat(sprintf("Filtered to %s college-educated employed workers with positive wages\n",
            format(nrow(acs_filtered), big.mark = ",")))

# Calculate mean wage by age and year
acs_age_wage <- acs_filtered %>%
  group_by(YEAR, AGE) %>%
  summarise(
    n_obs = n(),
    mean_wage = weighted.mean(INCWAGE, PERWT, na.rm = TRUE),
    .groups = "drop"
  )

cat(sprintf("Calculated mean wages for %d age-year combinations\n", nrow(acs_age_wage)))

# Calculate NPV multipliers ----------------------------------------------------
cat("\nCalculating NPV multipliers with discount rates of 3%% and 7%%...\n")

# Discount factors
beta3 <- 1 / 1.03  # 3% discount rate
beta7 <- 1 / 1.07  # 7% discount rate

# For each age, calculate expected lifetime earnings as a multiple of current wage
# Following EIG methodology: calculate through age 65 but cap multipliers at age 59
acs_npv_indices <- acs_age_wage %>%
  group_by(YEAR) %>%
  mutate(mean_wage_index = mean_wage / first(mean_wage)) %>%
  ungroup() %>%
  filter(AGE <= 65) %>%  # Assume retirement at 65
  group_by(YEAR) %>%
  # Calculate NPV of remaining lifetime earnings using reverse accumulation
  # (starting from age 65 and working backwards to current age)
  mutate(
    mean_wage_npv_3pct = rev(accumulate(rev(mean_wage_index), ~ .y + beta3 * .x)),
    mean_wage_npv_7pct = rev(accumulate(rev(mean_wage_index), ~ .y + beta7 * .x))
  ) %>%
  # Convert to multipliers (how many times current wage is lifetime earnings)
  mutate(
    exp_lifetime_multiplier_3pct = mean_wage_npv_3pct / mean_wage_index,
    exp_lifetime_multiplier_7pct = mean_wage_npv_7pct / mean_wage_index
  ) %>%
  ungroup() %>%
  # Keep only ages 22-59 for multipliers (EIG methodology)
  filter(AGE >= 22, AGE <= 59) %>%
  select(YEAR, AGE, n_obs, mean_wage,
         exp_lifetime_multiplier_3pct, exp_lifetime_multiplier_7pct)

# Find peak NPV ages
cat("\nPeak NPV ages by year:\n")
peak_npv_ages <- acs_npv_indices %>%
  group_by(YEAR) %>%
  summarise(
    peak_age_3pct = AGE[which.max(exp_lifetime_multiplier_3pct)],
    peak_age_7pct = AGE[which.max(exp_lifetime_multiplier_7pct)],
    .groups = "drop"
  )
print(peak_npv_ages)

# Save NPV multipliers ---------------------------------------------------------
cat("\nSaving NPV multipliers...\n")
dir.create("data/intermediate", showWarnings = FALSE, recursive = TRUE)

write_csv(acs_npv_indices,
          "data/intermediate/acs_npv_multipliers.csv")

cat("Saved to: data/intermediate/acs_npv_multipliers.csv\n")

# Show example multipliers for common ages
cat("\nExample multipliers for 2023 (most recent year, ages 22-59):\n")
example_multipliers <- acs_npv_indices %>%
  filter(YEAR == 2023, AGE %in% c(25, 30, 35, 40, 45, 50, 55)) %>%
  select(AGE, exp_lifetime_multiplier_3pct, exp_lifetime_multiplier_7pct)

print(example_multipliers, n = Inf)

################################################################################
# Step 2: Tag H-1B Petitions with Lifetime Earnings
################################################################################

cat("\n=== Step 2: Tag H-1B Petitions with Lifetime Earnings ===\n")

# Load H-1B data ---------------------------------------------------------------
cat("Loading H-1B petition data...\n")
h1b <- read_csv("data/processed/h1b_with_mincer_wages.csv",
                show_col_types = FALSE)

cat(sprintf("Loaded %s H-1B petitions\n", format(nrow(h1b), big.mark = ",")))

# Create lookup table for NPV multipliers --------------------------------------
# Use the most recent year (2023) for all petitions
# In your data, PW_year spans 2021-2023, but we'll use a single year's multipliers
# for simplicity. You could match on PW_year if you want year-specific multipliers.

npv_lookup <- acs_npv_indices %>%
  filter(YEAR == 2023) %>%
  select(AGE,
         lifetime_multiplier_3pct = exp_lifetime_multiplier_3pct,
         lifetime_multiplier_7pct = exp_lifetime_multiplier_7pct)

cat("Created NPV lookup table with multipliers for ages 22-59\n")

# Tag H-1B petitions with lifetime earnings ------------------------------------
cat("\nTagging H-1B petitions with lifetime earnings estimates...\n")

h1b_with_lifetime <- h1b %>%
  # Round age to nearest integer and cap at 59 (EIG methodology)
  # Workers under 22 get age 22 multiplier, workers 60+ get age 59 multiplier
  mutate(
    age_rounded = round(age),
    age_capped = case_when(
      age_rounded < 22 ~ 22,
      age_rounded > 59 ~ 59,
      TRUE ~ age_rounded
    )
  ) %>%
  # Join with NPV multipliers
  left_join(npv_lookup, by = c("age_capped" = "AGE")) %>%
  # Calculate lifetime earnings
  mutate(
    lifetime_earnings_3pct = petition_annual_pay_clean * lifetime_multiplier_3pct,
    lifetime_earnings_7pct = petition_annual_pay_clean * lifetime_multiplier_7pct
  ) %>%
  # Remove temporary columns
  select(-age_rounded, -age_capped)

# Check how many petitions got tagged
n_tagged <- sum(!is.na(h1b_with_lifetime$lifetime_earnings_3pct))
n_total <- nrow(h1b_with_lifetime)

cat(sprintf("Tagged %s of %s petitions (%.1f%%)\n",
            format(n_tagged, big.mark = ","),
            format(n_total, big.mark = ","),
            (n_tagged / n_total) * 100))

# Show summary statistics
cat("\nSummary statistics for lifetime earnings:\n")
summary_stats <- h1b_with_lifetime %>%
  filter(!is.na(lifetime_earnings_3pct)) %>%
  summarise(
    median_annual_pay = median(petition_annual_pay_clean, na.rm = TRUE),
    median_lifetime_3pct = median(lifetime_earnings_3pct, na.rm = TRUE),
    median_lifetime_7pct = median(lifetime_earnings_7pct, na.rm = TRUE),
    mean_annual_pay = mean(petition_annual_pay_clean, na.rm = TRUE),
    mean_lifetime_3pct = mean(lifetime_earnings_3pct, na.rm = TRUE),
    mean_lifetime_7pct = mean(lifetime_earnings_7pct, na.rm = TRUE)
  )

cat("\nMedian values:\n")
cat(sprintf("  Annual pay: $%s\n", format(round(summary_stats$median_annual_pay), big.mark = ",")))
cat(sprintf("  Lifetime earnings (3%% discount): $%s\n", format(round(summary_stats$median_lifetime_3pct), big.mark = ",")))
cat(sprintf("  Lifetime earnings (7%% discount): $%s\n", format(round(summary_stats$median_lifetime_7pct), big.mark = ",")))

cat("\nMean values:\n")
cat(sprintf("  Annual pay: $%s\n", format(round(summary_stats$mean_annual_pay), big.mark = ",")))
cat(sprintf("  Lifetime earnings (3%% discount): $%s\n", format(round(summary_stats$mean_lifetime_3pct), big.mark = ",")))
cat(sprintf("  Lifetime earnings (7%% discount): $%s\n", format(round(summary_stats$mean_lifetime_7pct), big.mark = ",")))

# Save tagged data -------------------------------------------------------------
cat("\nSaving H-1B data with lifetime earnings...\n")
write_csv(h1b_with_lifetime,
          "data/processed/h1b_with_lifetime_earnings.csv")

cat("Saved to: data/processed/h1b_with_lifetime_earnings.csv\n")

# Show example petitions -------------------------------------------------------
cat("\nExample petitions with lifetime earnings:\n")
examples <- h1b_with_lifetime %>%
  filter(!is.na(lifetime_earnings_3pct)) %>%
  select(age, petition_annual_pay_clean,
         lifetime_multiplier_3pct, lifetime_multiplier_7pct,
         lifetime_earnings_3pct, lifetime_earnings_7pct) %>%
  slice_sample(n = 5)

print(examples)

cat("\n=== Script Complete ===\n")
cat("Next steps:\n")
cat("  1. Use data/processed/h1b_with_lifetime_earnings.csv for policy analysis\n")
cat("  2. Filter lifetime earnings through weighted lottery, Experience Benchmarking, etc.\n")
cat("  3. Compare distributions of lifetime earnings across policies\n")
