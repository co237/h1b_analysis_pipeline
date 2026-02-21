# Export H-1B Records with Native Wage Comparisons
# This script creates a comprehensive output file with all H-1B workers (FY 2022-2024)
# and their matched native wage benchmarks across all control configurations
# Created: 2026-02-20

cat("\n=== Exporting H-1B Records with Native Wage Comparisons ===\n\n")

# Load configuration
source("config.R")

# Required packages
required_packages <- c("dplyr", "readr", "tidyr")
for (pkg in required_packages) {
  if (!require(pkg, character.only = TRUE)) {
    install.packages(pkg)
    library(pkg, character.only = TRUE)
  }
}

# Input file (output from step 2 geocoding)
h1b_file <- file.path(data_processed, "h1b_fy21_24_with_pumas.csv")

# Check if input exists
if (!file.exists(h1b_file)) {
  stop("Required input file not found: ", h1b_file, "\n",
       "Please run steps 1-2 of the pipeline first (data cleaning and geocoding).")
}

cat("Loading H-1B data with PUMAs...\n")
h1b_data <- read_csv(h1b_file, show_col_types = FALSE)

cat("  Records loaded:", nrow(h1b_data), "\n")
cat("  FY 2022-2024 records:", sum(h1b_data$registration_lottery_year %in% 2022:2024), "\n\n")

# The analysis script creates the native benchmarks, but we need to recreate them here
# Load ACS data
cat("Loading ACS microdata...\n")
library(ipumsr)

# Use the ACS file path from config.R
if (!file.exists(acs_ddi_file)) {
  stop("ACS IPUMS DDI file not found: ", acs_ddi_file, "\n",
       "Please ensure the ACS extract is in ", data_raw)
}

ddi <- read_ipums_ddi(acs_ddi_file)
acs_raw <- read_ipums_micro(ddi)

cat("  ACS records loaded:", nrow(acs_raw), "\n\n")

# Helper function: Map education codes
map_education_code <- function(edu_char) {
  case_when(
    edu_char == "A" ~ 1L,    # Less than high school
    edu_char == "B" ~ 63L,   # High school graduate
    edu_char == "C" ~ 65L,   # Some college
    edu_char == "D" ~ 71L,   # Associate degree
    edu_char == "E" ~ 101L,  # Bachelor's degree
    edu_char == "F" ~ 101L,  # Master's degree
    edu_char == "G" ~ 114L,  # Professional degree
    edu_char == "H" ~ 115L,  # Doctorate
    edu_char == "I" ~ 116L,  # Other doctorate
    TRUE ~ 0L
  )
}

# Prepare H-1B data
cat("Preparing H-1B panel data...\n")
h1b <- h1b_data %>%
  transmute(
    applicant_id,
    registration_lottery_year,
    YEAR = registration_lottery_year - 1,  # Employment year for matching
    AGE = registration_lottery_year - registration_birth_year,
    OCCSOC = as.character(as.numeric(gsub("-", "", SOC_CODE))),
    EDUCD = map_education_code(petition_beneficiary_edu_code),
    INCWAGE = petition_annual_pay_clean,
    h1b_dependent = petition_employer_h1b_dependent,
    wage_level = wage_level_combined,
    prior_visa = petition_beneficiary_classif,
    employer_name = registration_employer_name,
    SOC_TITLE,
    PUMA = case_when(
      YEAR == 2021 ~ as.character(PUMA_2010),
      YEAR >= 2022 ~ as.character(PUMA_2020),
      TRUE ~ NA_character_
    ),
    H1B = 1L,
    PERWT = 1
  ) %>%
  filter(!is.na(AGE), INCWAGE > 0, YEAR >= 2021) %>%
  mutate(
    EDUCD = as.factor(EDUCD),
    OCCSOC = as.factor(OCCSOC),
    age_grp = cut(AGE, breaks = c(20, 25, 30, 35, 40, 45, 50, 55, 60, 65),
                  right = FALSE, include.lowest = TRUE)
  )

cat("  H-1B records prepared:", nrow(h1b), "\n")
cat("  Year distribution:", paste(names(table(h1b$YEAR)), "=", table(h1b$YEAR), collapse = ", "), "\n\n")

# Prepare native data
cat("Preparing native-born panel data...\n")
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
    OCCSOC = as.character(as.numeric(OCCSOC)),
    EDUCD,
    INCWAGE,
    PUMA = if("PUMA" %in% names(acs_raw) && "STATEFIP" %in% names(acs_raw)) {
      paste0(sprintf("%02d", as.integer(STATEFIP)), sprintf("%05d", as.integer(PUMA)))
    } else {
      NA_character_
    },
    H1B = 0L,
    PERWT
  ) %>%
  mutate(
    EDUCD = as.factor(EDUCD),
    OCCSOC = as.factor(OCCSOC),
    age_grp = cut(AGE, breaks = c(20, 25, 30, 35, 40, 45, 50, 55, 60, 65),
                  right = FALSE, include.lowest = TRUE)
  )

cat("  Native records prepared:", nrow(natives), "\n\n")

# Combine panel
panel <- bind_rows(h1b, natives) %>%
  filter(INCWAGE > 0)

cat("Combined panel size:", nrow(panel), "\n")
cat("  H-1B workers:", sum(panel$H1B == 1), "\n")
cat("  Native-born workers:", sum(panel$H1B == 0), "\n\n")

# Load weighted median function
library(matrixStats)
weightedMedian <- function(x, w, na.rm = TRUE) {
  if (na.rm) {
    valid <- !is.na(x) & !is.na(w)
    x <- x[valid]
    w <- w[valid]
  }
  if (length(x) == 0) return(NA_real_)
  matrixStats::weightedMedian(x, w = w, na.rm = FALSE)
}

# Calculate native benchmarks for all control configurations
cat("Calculating native wage benchmarks...\n")

calc_native_median <- function(data, ...) {
  data %>%
    filter(H1B == 0) %>%
    group_by(...) %>%
    summarise(Native = weightedMedian(INCWAGE, w = PERWT, na.rm = TRUE), .groups = "drop")
}

native_median <- list(
  age_only = calc_native_median(panel, YEAR, age_grp),
  age_education = calc_native_median(panel, YEAR, EDUCD, age_grp),
  age_occupation = calc_native_median(panel, YEAR, OCCSOC, age_grp),
  full = calc_native_median(panel, YEAR, EDUCD, OCCSOC, age_grp),
  age_occ_ed_puma = calc_native_median(panel, YEAR, EDUCD, OCCSOC, age_grp, PUMA)
)

cat("  age_only:", nrow(native_median$age_only), "cells\n")
cat("  age_education:", nrow(native_median$age_education), "cells\n")
cat("  age_occupation:", nrow(native_median$age_occupation), "cells\n")
cat("  full:", nrow(native_median$full), "cells\n")
cat("  age_occ_ed_puma:", nrow(native_median$age_occ_ed_puma), "cells\n\n")

# Merge benchmarks with H-1B data
cat("Merging H-1B data with native benchmarks...\n")

h1b_only <- panel %>% filter(H1B == 1)

h1b_with_comparisons <- h1b_only %>%
  # Add age_only benchmark
  left_join(native_median$age_only %>% rename(native_wage_age_only = Native),
            by = c("YEAR", "age_grp")) %>%
  # Add age_education benchmark
  left_join(native_median$age_education %>% rename(native_wage_age_education = Native),
            by = c("YEAR", "EDUCD", "age_grp")) %>%
  # Add age_occupation benchmark
  left_join(native_median$age_occupation %>% rename(native_wage_age_occupation = Native),
            by = c("YEAR", "OCCSOC", "age_grp")) %>%
  # Add full controls benchmark
  left_join(native_median$full %>% rename(native_wage_full = Native),
            by = c("YEAR", "EDUCD", "OCCSOC", "age_grp")) %>%
  # Add age_occ_ed_puma benchmark
  left_join(native_median$age_occ_ed_puma %>% rename(native_wage_puma = Native),
            by = c("YEAR", "EDUCD", "OCCSOC", "age_grp", "PUMA")) %>%
  # Calculate wage premiums
  mutate(
    premium_age_only = INCWAGE - native_wage_age_only,
    premium_age_education = INCWAGE - native_wage_age_education,
    premium_age_occupation = INCWAGE - native_wage_age_occupation,
    premium_full = INCWAGE - native_wage_full,
    premium_puma = INCWAGE - native_wage_puma
  ) %>%
  # Select and order columns for output
  select(
    # Identifiers
    applicant_id,
    registration_lottery_year,
    employment_year = YEAR,

    # H-1B characteristics
    h1b_wage = INCWAGE,
    age = AGE,
    age_group = age_grp,
    education_code = EDUCD,
    occupation_soc = OCCSOC,
    occupation_title = SOC_TITLE,
    puma_code = PUMA,
    employer_name,
    h1b_dependent,
    wage_level,
    prior_visa,

    # Native wage benchmarks (labeled clearly)
    native_wage_age_only,
    native_wage_age_education,
    native_wage_age_occupation,
    native_wage_full,
    native_wage_puma,

    # Wage premiums (labeled clearly)
    premium_age_only,
    premium_age_education,
    premium_age_occupation,
    premium_full,
    premium_puma
  )

cat("  Records with benchmarks:", nrow(h1b_with_comparisons), "\n\n")

# Show merge rates
cat("Merge rates (% of H-1Bs matched to each benchmark):\n")
cat("  age_only:", sprintf("%.1f%%", 100 * mean(!is.na(h1b_with_comparisons$native_wage_age_only))), "\n")
cat("  age_education:", sprintf("%.1f%%", 100 * mean(!is.na(h1b_with_comparisons$native_wage_age_education))), "\n")
cat("  age_occupation:", sprintf("%.1f%%", 100 * mean(!is.na(h1b_with_comparisons$native_wage_age_occupation))), "\n")
cat("  full:", sprintf("%.1f%%", 100 * mean(!is.na(h1b_with_comparisons$native_wage_full))), "\n")
cat("  puma:", sprintf("%.1f%%", 100 * mean(!is.na(h1b_with_comparisons$native_wage_puma))), "\n\n")

# Export to CSV
output_file <- file.path(output_tables, "h1b_with_native_comparisons_fy2022_2024.csv")
cat("Exporting to:", output_file, "\n")
write_csv(h1b_with_comparisons, output_file)

cat("\n✓ Export complete!\n")
cat("  File size:", sprintf("%.1f MB", file.size(output_file) / 1024^2), "\n")
cat("  Records:", nrow(h1b_with_comparisons), "\n\n")

cat("Column definitions:\n")
cat("  - h1b_wage: Annual wage of H-1B worker\n")
cat("  - native_wage_*: Weighted median wage of comparable native-born workers\n")
cat("  - premium_*: Wage premium (h1b_wage - native_wage_*)\n")
cat("\nControl configurations:\n")
cat("  - age_only: Matched on employment_year + age_group\n")
cat("  - age_education: Matched on employment_year + education_code + age_group\n")
cat("  - age_occupation: Matched on employment_year + occupation_soc + age_group\n")
cat("  - full: Matched on employment_year + education_code + occupation_soc + age_group\n")
cat("  - puma: Matched on employment_year + education_code + occupation_soc + age_group + puma_code\n")
