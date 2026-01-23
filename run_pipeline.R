# ============================================================================
# H-1B Wage Premium Analysis Pipeline
# Main Orchestration Script
# ============================================================================
#
# This script runs the complete analysis pipeline:
#   1. Data cleaning (FOIA + LCA data)
#   2. Geocoding to PUMAs
#   3. Wage premium analysis with multiple control configurations
#
# Author: Connor O'Brien
# Created: 2026-01-23
# ============================================================================

cat("\n")
cat(paste(rep("=", 70), collapse = ""))
cat("\n            H-1B WAGE PREMIUM ANALYSIS PIPELINE\n")
cat(paste(rep("=", 70), collapse = ""))
cat("\n\n")

# Load configuration
source("config.R")

# Check R version
required_version <- "4.0.0"
if (getRversion() < required_version) {
  stop("This pipeline requires R version ", required_version, " or higher. ",
       "Current version: ", getRversion())
}

# Check required packages
required_packages <- c("readxl", "dplyr", "tidyr", "stringr", "fuzzyjoin",
                      "purrr", "tidygeocoder", "sf", "tidycensus", "ipumsr",
                      "tidyverse", "scales", "matrixStats", "readr", "knitr")

missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]

if (length(missing_packages) > 0) {
  cat("\nMissing required packages:", paste(missing_packages, collapse = ", "), "\n")
  cat("Installing missing packages...\n")
  install.packages(missing_packages)
}

# ============================================================================
# Pipeline Options
# ============================================================================

# Which steps to run? Set to FALSE to skip steps
run_step1_cleaning <- TRUE
run_step2_geocoding <- TRUE
run_step3_analysis <- TRUE

# Skip confirmation prompt?
skip_confirmation <- FALSE

# ============================================================================
# Pre-Flight Checks
# ============================================================================

cat("\n--- Pre-Flight Checks ---\n")

# Check for required input files
checks_passed <- TRUE

if (run_step1_cleaning) {
  cat("\nChecking for FOIA H-1B data files...\n")
  foia_missing <- character(0)
  for (file in foia_files) {
    fpath <- file.path(data_raw, file)
    if (!file.exists(fpath)) {
      foia_missing <- c(foia_missing, file)
    } else {
      cat("  Found:", file, "\n")
    }
  }
  if (length(foia_missing) > 0) {
    cat("\n  WARNING: Missing FOIA files:\n")
    cat("  ", paste(foia_missing, collapse = "\n   "), "\n")
    checks_passed <- FALSE
  }

  cat("\nChecking for LCA data directory...\n")
  if (!dir.exists(lca_data_path)) {
    cat("  WARNING: LCA data directory not found:", lca_data_path, "\n")
    checks_passed <- FALSE
  } else {
    cat("  Found:", lca_data_path, "\n")
  }
}

if (run_step3_analysis) {
  cat("\nChecking for ACS IPUMS data...\n")
  if (!file.exists(acs_ddi_file)) {
    cat("  WARNING: ACS DDI file not found:", acs_ddi_file, "\n")
    cat("  Please download ACS microdata from IPUMS (include PUMA variable)\n")
    checks_passed <- FALSE
  } else {
    cat("  Found:", acs_ddi_file, "\n")
  }

  cat("\nChecking for SOC definitions...\n")
  if (!file.exists(soc_definitions_file)) {
    cat("  WARNING: SOC definitions file not found:", soc_definitions_file, "\n")
    checks_passed <- FALSE
  } else {
    cat("  Found:", soc_definitions_file, "\n")
  }
}

if (!checks_passed) {
  cat("\n*** WARNINGS DETECTED ***\n")
  cat("Some required files are missing. Please review the warnings above.\n")
  cat("You can still proceed, but some steps may fail.\n\n")
}

# ============================================================================
# User Confirmation
# ============================================================================

if (!skip_confirmation) {
  cat("\n--- Pipeline Configuration ---\n")
  cat("Step 1 - Data Cleaning:  ", ifelse(run_step1_cleaning, "ENABLED", "SKIPPED"), "\n")
  cat("Step 2 - Geocoding:      ", ifelse(run_step2_geocoding, "ENABLED", "SKIPPED"), "\n")
  cat("Step 3 - Analysis:       ", ifelse(run_step3_analysis, "ENABLED", "SKIPPED"), "\n")
  cat("\nProceed with pipeline execution? (y/n): ")

  response <- tolower(trimws(readline()))
  if (response != "y" && response != "yes") {
    cat("\nPipeline execution cancelled by user.\n")
    quit(save = "no")
  }
}

# ============================================================================
# Execute Pipeline
# ============================================================================

# Set timezone explicitly (helps with macOS Apple Silicon issues)
Sys.setenv(TZ = "America/New_York")

cat("Recording pipeline start time...\n")
flush.console()
start_time <- Sys.time()
cat("Pipeline started at:", as.character(start_time), "\n")

cat("\n")
cat(paste(rep("=", 70), collapse = ""))
cat("\n                 STARTING PIPELINE EXECUTION\n")
cat(paste(rep("=", 70), collapse = ""))
cat("\n\n")

# Set timezone explicitly (helps with some macOS issues)
Sys.setenv(TZ = "America/New_York")

# --- STEP 1: Data Cleaning ---
if (run_step1_cleaning) {
  cat("\n")
  cat("=================================================================\n")
  cat("  STEP 1: DATA CLEANING\n")
  cat("=================================================================\n\n")

  cat("Recording start time...\n")
  flush.console()
  step1_start <- Sys.time()
  cat("Step 1 started at:", as.character(step1_start), "\n")

  tryCatch({
    source(file.path(scripts_dir, "01_data_cleaning.R"), local = FALSE)
    step1_duration <- difftime(Sys.time(), step1_start, units = "mins")
    cat("\n✓ Step 1 completed successfully in", round(step1_duration, 2), "minutes\n")
  }, error = function(e) {
    cat("\n✗ ERROR in Step 1:", conditionMessage(e), "\n")
    cat("Pipeline execution halted.\n")
    quit(save = "no", status = 1)
  })
} else {
  cat("\n[Step 1: Data Cleaning - SKIPPED]\n")
}

# --- STEP 2: Geocoding ---
if (run_step2_geocoding) {
  cat("\n")
  cat("=================================================================\n")
  cat("  STEP 2: GEOCODING TO PUMAs\n")
  cat("=================================================================\n\n")

  step2_start <- Sys.time()

  tryCatch({
    source(file.path(scripts_dir, "02_geocode_to_pumas.R"), local = FALSE)
    step2_duration <- difftime(Sys.time(), step2_start, units = "mins")
    cat("\n✓ Step 2 completed successfully in", round(step2_duration, 2), "minutes\n")
  }, error = function(e) {
    cat("\n✗ ERROR in Step 2:", conditionMessage(e), "\n")
    cat("Pipeline execution halted.\n")
    quit(save = "no", status = 1)
  })
} else {
  cat("\n[Step 2: Geocoding - SKIPPED]\n")
}

# --- STEP 3: Wage Premium Analysis ---
if (run_step3_analysis) {
  cat("\n")
  cat("=================================================================\n")
  cat("  STEP 3: WAGE PREMIUM ANALYSIS\n")
  cat("=================================================================\n\n")

  step3_start <- Sys.time()

  tryCatch({
    source(file.path(scripts_dir, "03_wage_premium_analysis.R"), local = FALSE)
    step3_duration <- difftime(Sys.time(), step3_start, units = "mins")
    cat("\n✓ Step 3 completed successfully in", round(step3_duration, 2), "minutes\n")
  }, error = function(e) {
    cat("\n✗ ERROR in Step 3:", conditionMessage(e), "\n")
    cat("Pipeline execution halted.\n")
    quit(save = "no", status = 1)
  })
} else {
  cat("\n[Step 3: Analysis - SKIPPED]\n")
}

# ============================================================================
# Pipeline Complete
# ============================================================================

total_duration <- difftime(Sys.time(), start_time, units = "mins")

cat("\n")
cat(paste(rep("=", 70), collapse = ""))
cat("\n                 PIPELINE EXECUTION COMPLETE\n")
cat(paste(rep("=", 70), collapse = ""))
cat("\n\n")
cat("Total execution time:", round(total_duration, 2), "minutes\n")
cat("\nOutput locations:\n")
cat("  - Cleaned data:      ", data_intermediate, "\n")
cat("  - Processed data:    ", data_processed, "\n")
cat("  - Figures:           ", output_figures, "\n")
cat("  - Tables:            ", output_tables, "\n")
cat("\n")
cat("All steps completed successfully!\n\n")
