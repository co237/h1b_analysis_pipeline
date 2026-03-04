# =============================================================================
# Test Script for Prevailing Wage Lookup Function
# =============================================================================
#
# This script demonstrates how to use the get_prevailing_wages() function
# to query specific wage scenarios.
#
# PREREQUISITE: Run Script 04 first to generate the required data files
# =============================================================================

# Load configuration and required libraries
source("config.R")
library(dplyr)

# Source Script 04 to get the function definition and load all required data
cat("Loading wage calculation infrastructure...\n")
cat("This may take 30-45 minutes if running for the first time...\n\n")

# Check if data already exists
if (file.exists(file.path(data_processed, "mincer_edu_exp_ratios.rds"))) {
  cat("Found existing Mincer ratios file. Loading minimal dependencies...\n\n")

  # Just source the function definition part (not the full estimation)
  # For now, we'll source the whole script but it will skip re-estimation
  source("scripts/04 Calculate new prevailing wages.R")
} else {
  cat("Mincer ratios not found. Running full Script 04...\n\n")
  source("scripts/04 Calculate new prevailing wages.R")
}

cat("\n=============================================================================\n")
cat("TESTING WAGE LOOKUP FUNCTION\n")
cat("=============================================================================\n\n")

# Example 1: Software Developer in San Francisco
cat("Example 1: Software Developer (15-1252)\n")
cat("Location: San Francisco MSA (41860)\n")
cat("Education: Bachelor's degree\n")
cat("Experience: 5 years\n")
cat("Year: 2023\n")
cat("Wage Type: Standard (ALC)\n\n")

result1 <- get_prevailing_wages(
  soc_code = "15-1252",
  education = "Bachelors",
  experience = 5,
  msa_code = "41860",
  year = 2023,
  wage_type = "ALC"
)

if (result1$status == "success") {
  cat("✓ Success!\n")
  cat("OFLC Level 3 (occupational median): $", format(result1$oflc_level3, big.mark = ","), "\n", sep = "")
  cat("Mincer wage at 50th percentile:     $", format(result1$pw_p50, big.mark = ","), "\n", sep = "")
  cat("Mincer wage at 62nd percentile:     $", format(result1$pw_p62, big.mark = ","), "\n", sep = "")
  cat("Mincer wage at 75th percentile:     $", format(result1$pw_p75, big.mark = ","), "\n", sep = "")
  cat("Mincer wage at 90th percentile:     $", format(result1$pw_p90, big.mark = ","), "\n", sep = "")
} else {
  cat("✗ Error:", result1$message, "\n")
}

cat("\n-----------------------------------------------------------------------------\n\n")

# Example 2: Mechanical Engineer in Houston with ACWIA
cat("Example 2: Mechanical Engineer (17-2141)\n")
cat("Location: Houston MSA (26420)\n")
cat("Education: Master's degree\n")
cat("Experience: 10 years\n")
cat("Year: 2023\n")
cat("Wage Type: ACWIA (EDC)\n\n")

result2 <- get_prevailing_wages(
  soc_code = "17-2141",
  education = "Masters",
  experience = 10,
  msa_code = "26420",
  year = 2023,
  wage_type = "EDC"
)

if (result2$status == "success") {
  cat("✓ Success!\n")
  cat("OFLC Level 3 (occupational median): $", format(result2$oflc_level3, big.mark = ","), "\n", sep = "")
  cat("Mincer wage at 50th percentile:     $", format(result2$pw_p50, big.mark = ","), "\n", sep = "")
  cat("Mincer wage at 62nd percentile:     $", format(result2$pw_p62, big.mark = ","), "\n", sep = "")
  cat("Mincer wage at 75th percentile:     $", format(result2$pw_p75, big.mark = ","), "\n", sep = "")
  cat("Mincer wage at 90th percentile:     $", format(result2$pw_p90, big.mark = ","), "\n", sep = "")
} else {
  cat("✗ Error:", result2$message, "\n")
}

cat("\n=============================================================================\n")
cat("TEST COMPLETE\n")
cat("=============================================================================\n\n")

cat("You can now use get_prevailing_wages() interactively.\n")
cat("Example:\n")
cat("  result <- get_prevailing_wages('15-1252', 'Bachelors', 5, '41860', 2023, 'ALC')\n")
cat("  result$pw_p50  # Get the 50th percentile wage\n\n")
