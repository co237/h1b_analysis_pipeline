################################################################################
# Script 09: Calculate Expected Lifetime Earnings for H-1B Petitions
#
# PURPOSE & METHODOLOGY:
# This script calculates Net Present Value (NPV) estimates of expected lifetime
# earnings for H-1B workers. The approach follows EIG's methodology:
#
# 1. Use ACS microdata to construct age-earnings profiles for college-educated
#    workers (how much the average college graduate earns at each age)
#
# 2. Calculate "NPV multipliers" that tell us: if you're age X earning $Y now,
#    your expected lifetime earnings (discounted to present value) will be Z
#    times your current salary
#
# 3. Apply these multipliers to each H-1B petition based on worker age
#
# EXAMPLE: A 30-year-old H-1B worker earning $100K might have a multiplier of
# 30.3 (with 3% discount rate), meaning expected lifetime earnings of $3.03M
#
# KEY ASSUMPTIONS:
# - Workers retire at age 65
# - Age-earnings trajectory follows that of college-educated workers in ACS
# - Future earnings are discounted at 3% or 7% per year (time value of money)
# - Workers under 22 use age 22 multiplier; workers 60+ use age 59 multiplier
#
# Inputs:  - data/raw/usa_00076.dat.gz (IPUMS ACS microdata, 2021-2023)
#          - data/raw/usa_00076.xml (IPUMS data dictionary)
#          - data/processed/h1b_with_mincer_wages.csv (H-1B petition data)
#
# Outputs: - data/intermediate/acs_npv_multipliers.csv (age-specific multipliers)
#          - data/processed/h1b_with_lifetime_earnings.csv (H-1B data with NPV)
#
# Author: Connor O'Brien / Institute for Progress
# Date: March 2026
################################################################################

# Load required libraries ------------------------------------------------------
library(ipumsr)   # For reading IPUMS ACS microdata
library(dplyr)    # For data manipulation
library(purrr)    # For accumulate() function in NPV calculation
library(slider)   # For rolling window calculations (not used but kept for compatibility)
library(readr)    # For reading/writing CSV files

cat("=== Step 1: Calculate NPV Multipliers from ACS Data ===\n")

################################################################################
# STEP 1A: Load and Filter ACS Microdata
################################################################################

cat("Loading IPUMS ACS microdata (usa_00076)...\n")

# Read IPUMS data dictionary (DDI) and microdata
# The DDI file contains variable definitions and labels
ddi_acs <- read_ipums_ddi("data/raw/usa_00076.xml")
acs <- read_ipums_micro(ddi_acs)

cat(sprintf("Loaded %s ACS observations\n", format(nrow(acs), big.mark = ",")))

# Filter to relevant population ------------------------------------------------
cat("\nCalculating age-wage profiles...\n")

# IMPORTANT: We filter to college-educated employed workers with positive wages
# This matches EIG's methodology and ensures our age-earnings profiles reflect
# the H-1B population (who are overwhelmingly college-educated)
#
# If we used ALL workers (including non-college), the age-earnings profile would
# be much flatter and lifetime earnings estimates would be too low
#
# Filter criteria:
# - EDUCD >= 101: Bachelor's degree or higher (codes 101-116 in IPUMS)
# - EMPSTAT == 1: Currently employed (excludes unemployed and not in labor force)
# - INCWAGE > 0: Positive wage/salary income (excludes zero earners)
# - AGE <= 71: Working ages (we calculate through retirement at 65)
#
# We also "bottom-code" age at 22, meaning workers younger than 22 are treated
# as 22-year-olds. This prevents very young workers (age 16-21) from distorting
# the early career earnings profile.

acs_filtered <- acs %>%
  filter(
    EDUCD >= 101,        # Bachelor's degree or higher
    EMPSTAT == 1,        # Employed
    INCWAGE > 0,         # Positive wage income
    AGE <= 71            # Working ages through retirement
  ) %>%
  mutate(AGE = ifelse(AGE < 22, 22, AGE))  # Bottom-code age at 22

cat(sprintf("Filtered to %s college-educated employed workers with positive wages\n",
            format(nrow(acs_filtered), big.mark = ",")))

################################################################################
# STEP 1B: Calculate Mean Wage by Age and Year
################################################################################

# Calculate the average wage at each age, using person weights (PERWT) to make
# the sample representative of the U.S. population
#
# WHAT ARE PERSON WEIGHTS?
# Each ACS observation represents multiple people in the population. PERWT tells
# us how many people each observation represents. Using weighted.mean() ensures
# our averages reflect the true population, not just the survey sample.
#
# OUTPUT: For each combination of YEAR and AGE, we get the mean wage income

acs_age_wage <- acs_filtered %>%
  group_by(YEAR, AGE) %>%
  summarise(
    n_obs = n(),                                              # Sample size at this age
    mean_wage = weighted.mean(INCWAGE, PERWT, na.rm = TRUE), # Population-weighted mean wage
    .groups = "drop"
  )

cat(sprintf("Calculated mean wages for %d age-year combinations\n", nrow(acs_age_wage)))

################################################################################
# STEP 1C: Calculate NPV Multipliers Using Reverse Accumulation
################################################################################

cat("\nCalculating NPV multipliers with discount rates of 3%% and 7%%...\n")

# DISCOUNT RATES: Why do we discount future earnings?
# $1 earned today is worth more than $1 earned 10 years from now because:
# (1) You could invest today's dollar and earn returns
# (2) Inflation erodes purchasing power
# (3) There's risk/uncertainty about future earnings
#
# The discount factor tells us how much future dollars are worth today:
# - 3% discount: $1 next year = $0.971 today (1/1.03)
# - 7% discount: $1 next year = $0.935 today (1/1.07)
#
# We use TWO discount rates (3% and 7%) to provide a range of estimates:
# - 3% is typical for long-run real economic growth (conservative/high NPV)
# - 7% is typical for private sector discount rates (aggressive/low NPV)

beta3 <- 1 / 1.03  # 3% discount rate → beta = 0.9709
beta7 <- 1 / 1.07  # 7% discount rate → beta = 0.9346

# ALGORITHM: Reverse Accumulation Method for NPV Calculation
#
# We calculate NPV using "reverse accumulation" - starting at retirement (age 65)
# and working backwards to each younger age.
#
# EXAMPLE: How much is a 30-year-old's future earnings stream worth today?
# - At age 65: mean_wage[65] (no discounting, it's the final year)
# - At age 64: mean_wage[64] + beta * mean_wage[65]
# - At age 63: mean_wage[63] + beta * (mean_wage[64] + beta * mean_wage[65])
# - ... continue backwards to age 30
#
# The accumulate() function does this recursively:
# Starting from age 65, we accumulate backwards: new_value = current_wage + beta * accumulated_so_far
#
# NORMALIZATION: We express NPV as a "multiplier" of current wage
# This allows us to easily calculate lifetime earnings for H-1B workers:
# lifetime_earnings = current_salary × multiplier
#
# The multiplier tells us: "Your future earnings are X times your current salary"

acs_npv_indices <- acs_age_wage %>%
  group_by(YEAR) %>%

  # Step 1: Create wage index (normalize to age 22 = 1.0)
  # This makes wages comparable across ages by expressing them relative to age 22
  # Example: If age 30 earns $80K and age 22 earns $50K, index = 1.6
  mutate(mean_wage_index = mean_wage / first(mean_wage)) %>%

  ungroup() %>%
  filter(AGE <= 65) %>%  # Only calculate through retirement at 65
  group_by(YEAR) %>%

  # Step 2: Calculate NPV using reverse accumulation
  # rev() reverses the order (so we start at age 65)
  # accumulate() recursively applies: new_value = current + beta * previous
  # Then rev() again to restore original age order
  #
  # INTUITION: At age 64, your lifetime earnings = your age 64 earnings +
  # discounted value of all your age 65 earnings
  mutate(
    mean_wage_npv_3pct = rev(accumulate(rev(mean_wage_index), ~ .y + beta3 * .x)),
    mean_wage_npv_7pct = rev(accumulate(rev(mean_wage_index), ~ .y + beta7 * .x))
  ) %>%

  # Step 3: Convert NPV to multipliers
  # Divide total NPV by current wage index to get "how many times current wage"
  # Example: If age 30 NPV = 48 and wage index = 1.6, multiplier = 30
  # Meaning: 30-year-old's lifetime earnings = 30 × current salary
  mutate(
    exp_lifetime_multiplier_3pct = mean_wage_npv_3pct / mean_wage_index,
    exp_lifetime_multiplier_7pct = mean_wage_npv_7pct / mean_wage_index
  ) %>%

  ungroup() %>%

  # Step 4: Keep only ages 22-59 (EIG methodology)
  # WHY? EIG found that workers aged 60+ are atypical in the H-1B program
  # and may have different earnings trajectories. To avoid extrapolation issues,
  # workers 60+ are assigned the age 59 multiplier.
  filter(AGE >= 22, AGE <= 59) %>%

  # Keep relevant columns
  select(YEAR, AGE, n_obs, mean_wage,
         exp_lifetime_multiplier_3pct, exp_lifetime_multiplier_7pct)

# DIAGNOSTIC: Find peak NPV age ------------------------------------------------
# At what age is lifetime NPV highest? This tells us the "optimal" age for
# lifetime earnings potential (it's usually young, since you have more years
# to work and earn)

cat("\nPeak NPV ages by year:\n")
peak_npv_ages <- acs_npv_indices %>%
  group_by(YEAR) %>%
  summarise(
    peak_age_3pct = AGE[which.max(exp_lifetime_multiplier_3pct)],
    peak_age_7pct = AGE[which.max(exp_lifetime_multiplier_7pct)],
    .groups = "drop"
  )
print(peak_npv_ages)
# Result: Age 22 has highest multipliers (they have the most career ahead)

################################################################################
# STEP 1D: Save NPV Multipliers as Lookup Table
################################################################################

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

# INTERPRETATION OF MULTIPLIERS:
# Age 25 with multiplier 41.2 (3% discount) means:
# - A 25-year-old earning $100K will earn $4.12M over their lifetime (NPV)
# - This includes their current $100K plus all future raises/earnings through age 65
# - Discounted back to present value at 3% per year

################################################################################
# STEP 2: Tag H-1B Petitions with Lifetime Earnings
################################################################################

cat("\n=== Step 2: Tag H-1B Petitions with Lifetime Earnings ===\n")

# Load H-1B data ---------------------------------------------------------------
cat("Loading H-1B petition data...\n")
h1b <- read_csv("data/processed/h1b_with_mincer_wages.csv",
                show_col_types = FALSE)

cat(sprintf("Loaded %s H-1B petitions\n", format(nrow(h1b), big.mark = ",")))

################################################################################
# STEP 2A: Create Lookup Table from 2023 Multipliers
################################################################################

# DESIGN CHOICE: Use 2023 multipliers for all H-1B workers
#
# The H-1B data spans 2021-2023, but we use 2023 multipliers for everyone
# for simplicity. We could match workers to their petition year's multipliers,
# but the year-to-year variation in multipliers is small (~1-2%) and doesn't
# materially affect policy comparisons.
#
# This is a reasonable approximation that simplifies the analysis.

npv_lookup <- acs_npv_indices %>%
  filter(YEAR == 2023) %>%
  select(AGE,
         lifetime_multiplier_3pct = exp_lifetime_multiplier_3pct,
         lifetime_multiplier_7pct = exp_lifetime_multiplier_7pct)

cat("Created NPV lookup table with multipliers for ages 22-59\n")

################################################################################
# STEP 2B: Join Multipliers to H-1B Data and Calculate Lifetime Earnings
################################################################################

cat("\nTagging H-1B petitions with lifetime earnings estimates...\n")

# ALGORITHM:
# 1. Round each worker's age to nearest integer (for lookup)
# 2. Cap ages at 22 (low end) and 59 (high end) per EIG methodology
# 3. Join with NPV multipliers by age
# 4. Calculate lifetime earnings = annual_salary × multiplier

h1b_with_lifetime <- h1b %>%

  # Step 1: Prepare age for lookup
  mutate(
    age_rounded = round(age),

    # Cap ages following EIG methodology:
    # - Workers under 22: Use age 22 multiplier (avoid extrapolation)
    # - Workers 60+: Use age 59 multiplier (small/atypical sample in H-1B data)
    age_capped = case_when(
      age_rounded < 22 ~ 22,   # Bottom-code at 22
      age_rounded > 59 ~ 59,   # Top-code at 59
      TRUE ~ age_rounded       # Otherwise use actual age
    )
  ) %>%

  # Step 2: Join with NPV multipliers
  # This performs a left join, matching each H-1B worker's age to the
  # corresponding multiplier from the ACS-based lookup table
  left_join(npv_lookup, by = c("age_capped" = "AGE")) %>%

  # Step 3: Calculate lifetime earnings
  # Simply multiply annual salary by the age-specific multiplier
  # EXAMPLE: 30-year-old earning $100K with multiplier 30.3 → $3.03M lifetime
  mutate(
    lifetime_earnings_3pct = petition_annual_pay_clean * lifetime_multiplier_3pct,
    lifetime_earnings_7pct = petition_annual_pay_clean * lifetime_multiplier_7pct
  ) %>%

  # Step 4: Clean up temporary columns
  select(-age_rounded, -age_capped)

################################################################################
# STEP 2C: Validation and Summary Statistics
################################################################################

# Check coverage: How many petitions successfully got tagged?
n_tagged <- sum(!is.na(h1b_with_lifetime$lifetime_earnings_3pct))
n_total <- nrow(h1b_with_lifetime)

cat(sprintf("Tagged %s of %s petitions (%.1f%%)\n",
            format(n_tagged, big.mark = ","),
            format(n_total, big.mark = ","),
            (n_tagged / n_total) * 100))

# Should be 100% since we cap ages at 22-59 (all ages covered by lookup table)

# Calculate summary statistics -------------------------------------------------
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

# INTERPRETATION:
# - Median lifetime earnings ~$2.68M (3%) means half of H-1B workers are expected
#   to earn more than $2.68M over their careers (in present value terms)
# - The 7% discount gives lower values (~$1.62M) because it places less value
#   on future earnings (higher time preference)

################################################################################
# STEP 2D: Save Final Dataset
################################################################################

cat("\nSaving H-1B data with lifetime earnings...\n")
write_csv(h1b_with_lifetime,
          "data/processed/h1b_with_lifetime_earnings.csv")

cat("Saved to: data/processed/h1b_with_lifetime_earnings.csv\n")

# Show random examples ---------------------------------------------------------
cat("\nExample petitions with lifetime earnings:\n")
examples <- h1b_with_lifetime %>%
  filter(!is.na(lifetime_earnings_3pct)) %>%
  select(age, petition_annual_pay_clean,
         lifetime_multiplier_3pct, lifetime_multiplier_7pct,
         lifetime_earnings_3pct, lifetime_earnings_7pct) %>%
  slice_sample(n = 5)

print(examples)

################################################################################
# NEXT STEPS
################################################################################

cat("\n=== Script Complete ===\n")
cat("Next steps:\n")
cat("  1. Use data/processed/h1b_with_lifetime_earnings.csv for policy analysis\n")
cat("  2. Filter lifetime earnings through weighted lottery, Experience Benchmarking, etc.\n")
cat("  3. Compare distributions of lifetime earnings across policies\n")
cat("\nThe lifetime earnings columns can now be used in Script 08 to analyze:\n")
cat("  - Which policies select higher-earning workers?\n")
cat("  - How does the weighted lottery affect lifetime earnings distributions?\n")
cat("  - What is the economic value of different H-1B selection mechanisms?\n")
