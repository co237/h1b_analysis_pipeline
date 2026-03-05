# =============================================================================
# INTERACTIVE PREVAILING WAGE CALCULATOR
# =============================================================================
#
# This script calculates Experience Benchmarking prevailing wages for any
# combination of occupation, education, experience, location, and year.
#
# PREREQUISITE: Run Script 04 first to generate the required data files
#
# USAGE IN RSTUDIO:
#   1. Edit the parameters in the "USER INPUTS" section below (lines 20-40)
#   2. Run the entire script (Ctrl/Cmd + Shift + Enter)
#   3. View results in the console
#
# =============================================================================


# =============================================================================
# ========== USER INPUTS - EDIT YOUR PARAMETERS HERE =========================
# =============================================================================

# OCCUPATION (SOC Code) - 6-digit code with or without hyphen
# Examples: "15-1252" (Software Developers), "17-2141" (Mechanical Engineers),
#           "29-1141" (Registered Nurses), "13-2011" (Accountants)
SOC_CODE <- "17-2051"

# EDUCATION LEVEL - Must be one of the following (keep quotes):
#   "Less than HS", "High school", "Some college", "Associates",
#   "Bachelors", "Masters", "Prof degree", "PhD"
EDUCATION <- "Bachelors"

# YEARS OF EXPERIENCE - Number between 0 and 50
EXPERIENCE <- 15

# AREA (MSA Code) - 5-digit metropolitan area code
# Examples: "41860" (San Francisco), "35620" (New York City),
#           "26420" (Houston), "31080" (Los Angeles)
MSA_CODE <- "41860"

# YEAR - Between 2021 and 2026
YEAR <- 2026

# PREVAILING WAGE TYPE - Either "ALC" (standard) or "EDC" (ACWIA)
WAGE_TYPE <- "ALC"

# =============================================================================
# ========== END OF USER INPUTS ===============================================
# =============================================================================


# =============================================================================
# Load the wage calculation infrastructure
# =============================================================================

# Suppress startup messages for cleaner output
suppressPackageStartupMessages({
  if (!require("dplyr", quietly = TRUE)) {
    stop("Package 'dplyr' is required. Install with: install.packages('dplyr')")
  }
})

cat("\n")
cat("===============================================================================\n")
cat("                    EXPERIENCE BENCHMARKING WAGE CALCULATOR                   \n")
cat("===============================================================================\n\n")

cat("Loading wage calculation function and data...\n")

# Load the main lookup function
if (file.exists("lookup_wages.R")) {
  suppressMessages(source("lookup_wages.R", echo = FALSE))
} else if (file.exists("../lookup_wages.R")) {
  suppressMessages(source("../lookup_wages.R", echo = FALSE))
} else {
  stop("\nERROR: Cannot find lookup_wages.R\n",
       "Please make sure you're running this script from the project root or scripts directory.")
}

# =============================================================================
# Display input parameters
# =============================================================================

cat("\n")
cat("-------------------------------------------------------------------------------\n")
cat("INPUT PARAMETERS\n")
cat("-------------------------------------------------------------------------------\n")
cat(sprintf("  Occupation (SOC):      %-20s\n", SOC_CODE))
cat(sprintf("  Education:             %-20s\n", EDUCATION))
cat(sprintf("  Experience:            %-20s\n", paste(EXPERIENCE, "years")))
cat(sprintf("  Area (MSA):            %-20s\n", MSA_CODE))
cat(sprintf("  Year:                  %-20s\n", YEAR))
cat(sprintf("  Wage Type:             %-20s\n",
    ifelse(WAGE_TYPE == "ALC", "ALC (Standard)", "EDC (ACWIA)")))
cat("-------------------------------------------------------------------------------\n\n")

cat("Calculating prevailing wages...\n")

# =============================================================================
# Run the wage calculation
# =============================================================================

result <- get_prevailing_wages(
  soc_code = SOC_CODE,
  education = EDUCATION,
  experience = EXPERIENCE,
  msa_code = MSA_CODE,
  year = YEAR,
  wage_type = WAGE_TYPE
)

# =============================================================================
# Display results
# =============================================================================

cat("\n")
cat("===============================================================================\n")
cat("                                   RESULTS                                     \n")
cat("===============================================================================\n\n")

if (result$status == "success") {

  # Success message
  cat("\u2713 Calculation successful!\n\n")

  # Basic information
  cat("WORKER PROFILE:\n")
  cat(sprintf("  SOC Code:              %s\n", result$soc_code))
  cat(sprintf("  ACS Occupation Code:   %s\n", result$acs_occsoc))
  cat(sprintf("  Education Level:       %s\n", result$education))
  cat(sprintf("  Years of Experience:   %d\n", result$experience))
  cat(sprintf("  MSA Code:              %s\n", result$msa_code))
  cat(sprintf("  Year:                  %d\n", result$year))
  cat(sprintf("  Wage Type:             %s\n\n", result$wage_type))

  # Occupational median (OFLC Level 3)
  cat("-------------------------------------------------------------------------------\n")
  cat("OCCUPATIONAL MEDIAN (OFLC Level 3)\n")
  cat("-------------------------------------------------------------------------------\n")
  cat(sprintf("  Area-Occupation Median:    $%s\n",
              format(result$oflc_level3, big.mark = ",", nsmall = 2)))
  cat("\n  This is the median wage for ALL workers in this occupation and area,\n")
  cat("  regardless of education or experience.\n\n")

  # Experience Benchmarking wage levels
  cat("-------------------------------------------------------------------------------\n")
  cat("EXPERIENCE BENCHMARKING PREVAILING WAGES\n")
  cat("-------------------------------------------------------------------------------\n")
  cat("  These wages are adjusted for the worker's specific education and experience:\n\n")

  cat(sprintf("  Level I   (50th percentile):   $%s\n",
              format(result$pw_p50, big.mark = ",", nsmall = 2)))
  cat(sprintf("  Level II  (62nd percentile):   $%s\n",
              format(result$pw_p62, big.mark = ",", nsmall = 2)))
  cat(sprintf("  Level III (75th percentile):   $%s\n",
              format(result$pw_p75, big.mark = ",", nsmall = 2)))
  cat(sprintf("  Level IV  (90th percentile):   $%s\n\n",
              format(result$pw_p90, big.mark = ",", nsmall = 2)))

  # Education-experience adjustment
  cat("-------------------------------------------------------------------------------\n")
  cat("EDUCATION-EXPERIENCE ADJUSTMENT\n")
  cat("-------------------------------------------------------------------------------\n")
  cat(sprintf("  Adjustment Ratio:          %.4f\n", result$ratio_p50))
  cat("\n  This worker's education-experience combination adjusts their wage\n")
  cat(sprintf("  to %.1f%% of the occupational median.\n\n", result$ratio_p50 * 100))

  # Comparison to median
  if (result$ratio_p50 > 1.0) {
    pct_diff <- (result$ratio_p50 - 1.0) * 100
    cat(sprintf("  \u2192 This combination earns %.1f%% MORE than the typical worker\n", pct_diff))
    cat("     in this occupation.\n")
  } else if (result$ratio_p50 < 1.0) {
    pct_diff <- (1.0 - result$ratio_p50) * 100
    cat(sprintf("  \u2192 This combination earns %.1f%% LESS than the typical worker\n", pct_diff))
    cat("     in this occupation.\n")
  } else {
    cat("  \u2192 This combination earns the same as the typical worker\n")
    cat("     in this occupation.\n")
  }

  # Percentile scaling information
  cat("\n")
  cat("-------------------------------------------------------------------------------\n")
  cat("PERCENTILE SCALING FACTORS\n")
  cat("-------------------------------------------------------------------------------\n")
  cat("  These show how the four wage levels relate to the 50th percentile:\n\n")
  cat(sprintf("  50th to 62nd percentile:   %.4f (%.1f%% increase)\n",
              result$ratio_p62 / result$ratio_p50,
              ((result$ratio_p62 / result$ratio_p50) - 1) * 100))
  cat(sprintf("  50th to 75th percentile:   %.4f (%.1f%% increase)\n",
              result$ratio_p75 / result$ratio_p50,
              ((result$ratio_p75 / result$ratio_p50) - 1) * 100))
  cat(sprintf("  50th to 90th percentile:   %.4f (%.1f%% increase)\n",
              result$ratio_p90 / result$ratio_p50,
              ((result$ratio_p90 / result$ratio_p50) - 1) * 100))

} else {

  # Error message
  cat("\u2717 ERROR: Wage calculation failed.\n\n")
  cat("ERROR DETAILS:\n")
  cat(result$message, "\n")
  cat("\n")
  cat("TROUBLESHOOTING:\n")
  cat("  - Check that the SOC code is valid (6 digits, e.g., '15-1252')\n")
  cat("  - Verify the MSA code exists in OFLC data for this year\n")
  cat("  - Confirm education level matches one of the valid options\n")
  cat("  - Ensure experience is between 0 and 50 years\n")
  cat("  - Check that the year is between 2021 and 2026\n")

}

cat("\n")
cat("===============================================================================\n")
cat("                              END OF CALCULATION                               \n")
cat("===============================================================================\n\n")

if (result$status == "success") {
  cat("To run another calculation:\n")
  cat("  1. Edit the parameters in the 'USER INPUTS' section (lines 20-40)\n")
  cat("  2. Run the entire script again\n\n")

  cat("For programmatic access, use:\n")
  cat("  source('lookup_wages.R')\n")
  cat("  result <- get_prevailing_wages(soc_code, education, experience, msa, year, type)\n\n")
}
