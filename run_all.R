# ==============================================================================
# DOL NPRM Prevailing Wage Analysis - Master Pipeline Script
# ==============================================================================
#
# This script runs the complete analysis pipeline from raw data to final
# NPRM simulation results. All intermediate CSV files are saved at each step.
#
# PREREQUISITES:
#   - All required data files must be in data/raw/ (see README.md)
#   - Required R packages must be installed (see README.md)
#   - Working directory must be the project root
#
# RUNTIME: ~1.5-2 hours for full pipeline
#
# ==============================================================================

cat("\n")
cat("==============================================================================\n")
cat("         DOL NPRM PREVAILING WAGE ANALYSIS - FULL PIPELINE\n")
cat("==============================================================================\n\n")

# Record start time
pipeline_start <- Sys.time()

# Check working directory
if (!file.exists("config.R")) {
  stop("ERROR: Cannot find config.R\n",
       "Please make sure your working directory is set to the project root.\n",
       "You can use setwd() or open the .Rproj file in RStudio.")
}

cat("Working directory:", getwd(), "\n")
cat("Start time:", format(pipeline_start, "%Y-%m-%d %H:%M:%S"), "\n\n")

# ==============================================================================
# STEP 1: Data Cleaning
# ==============================================================================

cat("\n")
cat("==============================================================================\n")
cat("  STEP 1 of 7: Data Cleaning\n")
cat("==============================================================================\n\n")

step1_start <- Sys.time()

tryCatch({
  source("scripts/01_data_cleaning.R", local = FALSE)

  step1_time <- difftime(Sys.time(), step1_start, units = "mins")
  cat(sprintf("\n✓ Step 1 completed in %.1f minutes\n", step1_time))

  # Verify output was created
  if (!file.exists("data/intermediate/h1b_fy21_24_cleaned.csv")) {
    warning("Expected output file not found: data/intermediate/h1b_fy21_24_cleaned.csv")
  } else {
    file_size <- file.info("data/intermediate/h1b_fy21_24_cleaned.csv")$size / 1024^2
    cat(sprintf("Output file created: %.1f MB\n", file_size))
  }

}, error = function(e) {
  cat("\n✗ ERROR in Step 1:\n")
  cat("  ", conditionMessage(e), "\n\n")
  stop("Pipeline halted at Step 1")
})

# ==============================================================================
# STEP 2: Geocode to PUMAs
# ==============================================================================

cat("\n")
cat("==============================================================================\n")
cat("  STEP 2 of 7: Geocode to PUMAs\n")
cat("==============================================================================\n\n")

step2_start <- Sys.time()

tryCatch({
  source("scripts/02_geocode_to_pumas.R", local = FALSE)

  step2_time <- difftime(Sys.time(), step2_start, units = "mins")
  cat(sprintf("\n✓ Step 2 completed in %.1f minutes\n", step2_time))

  if (!file.exists("data/processed/h1b_fy21_24_with_pumas.csv")) {
    warning("Expected output file not found: data/processed/h1b_fy21_24_with_pumas.csv")
  } else {
    file_size <- file.info("data/processed/h1b_fy21_24_with_pumas.csv")$size / 1024^2
    cat(sprintf("Output file created: %.1f MB\n", file_size))
  }

}, error = function(e) {
  cat("\n✗ ERROR in Step 2:\n")
  cat("  ", conditionMessage(e), "\n\n")
  stop("Pipeline halted at Step 2")
})

# ==============================================================================
# STEP 3: Interpolate Wage Percentiles
# ==============================================================================

cat("\n")
cat("==============================================================================\n")
cat("  STEP 3 of 7: Interpolate Wage Percentiles\n")
cat("==============================================================================\n\n")

step3_start <- Sys.time()

tryCatch({
  source("scripts/03 interpolate wage percentiles.R", local = FALSE)

  step3_time <- difftime(Sys.time(), step3_start, units = "mins")
  cat(sprintf("\n✓ Step 3 completed in %.1f minutes\n", step3_time))

  if (!file.exists("data/processed/h1b_with_percentiles_and_native_comps.csv")) {
    warning("Expected output file not found: data/processed/h1b_with_percentiles_and_native_comps.csv")
  } else {
    file_size <- file.info("data/processed/h1b_with_percentiles_and_native_comps.csv")$size / 1024^2
    cat(sprintf("Output file created: %.1f MB\n", file_size))
  }

}, error = function(e) {
  cat("\n✗ ERROR in Step 3:\n")
  cat("  ", conditionMessage(e), "\n\n")
  stop("Pipeline halted at Step 3")
})

# ==============================================================================
# STEPS 4-5: Calculate Mincer Wages and Apply to Petitions
# ==============================================================================
# Note: These must run in the same R session because Step 5 requires
# model objects from Step 4 that are held in memory

cat("\n")
cat("==============================================================================\n")
cat("  STEP 4 of 7: Calculate Mincer Prevailing Wages\n")
cat("==============================================================================\n\n")

step4_start <- Sys.time()

tryCatch({
  source("scripts/04 Calculate new prevailing wages.R", local = FALSE)

  step4_time <- difftime(Sys.time(), step4_start, units = "mins")
  cat(sprintf("\n✓ Step 4 completed in %.1f minutes\n", step4_time))

  # Verify model objects were created
  if (!exists("occ_edu_exp_ratios") || !exists("oflc_bases")) {
    stop("Step 4 did not create required objects: occ_edu_exp_ratios, oflc_bases")
  }
  cat("Mincer education-experience ratios and OFLC data loaded in memory\n")

  if (!file.exists("output/tables/occ_model_coefficients.csv")) {
    warning("Expected output file not found: output/tables/occ_model_coefficients.csv")
  }

}, error = function(e) {
  cat("\n✗ ERROR in Step 4:\n")
  cat("  ", conditionMessage(e), "\n\n")
  stop("Pipeline halted at Step 4")
})

# Do NOT run gc() here - we need to preserve the model objects in memory

cat("\n")
cat("==============================================================================\n")
cat("  STEP 5 of 7: Apply Mincer Wages to H-1B Petitions\n")
cat("==============================================================================\n\n")

step5_start <- Sys.time()

tryCatch({
  source("scripts/05 Apply new PWs to H1B petitions.R", local = FALSE)

  step5_time <- difftime(Sys.time(), step5_start, units = "mins")
  cat(sprintf("\n✓ Step 5 completed in %.1f minutes\n", step5_time))

  if (!file.exists("data/processed/h1b_with_mincer_wages.csv")) {
    warning("Expected output file not found: data/processed/h1b_with_mincer_wages.csv")
  } else {
    file_size <- file.info("data/processed/h1b_with_mincer_wages.csv")$size / 1024^2
    cat(sprintf("Output file created: %.1f MB\n", file_size))
  }

}, error = function(e) {
  cat("\n✗ ERROR in Step 5:\n")
  cat("  ", conditionMessage(e), "\n\n")
  stop("Pipeline halted at Step 5")
})

# ==============================================================================
# STEP 6: NPRM Simulation
# ==============================================================================

cat("\n")
cat("==============================================================================\n")
cat("  STEP 6 of 7: NPRM Simulation\n")
cat("==============================================================================\n\n")

cat("NOTE: Step 6 is designed for interactive use.\n")
cat("You can adjust policy scenarios by editing the threshold parameters in:\n")
cat("  scripts/06 nprm_simulation.R\n\n")
cat("Running with default thresholds...\n\n")

step6_start <- Sys.time()

tryCatch({
  source("scripts/06 nprm_simulation.R", local = FALSE)

  step6_time <- difftime(Sys.time(), step6_start, units = "mins")
  cat(sprintf("\n✓ Step 6 completed in %.1f minutes\n", step6_time))

}, error = function(e) {
  cat("\n✗ ERROR in Step 6:\n")
  cat("  ", conditionMessage(e), "\n\n")
  stop("Pipeline halted at Step 6")
})

# ==============================================================================
# STEP 7: Economic Analysis
# ==============================================================================

cat("\n")
cat("==============================================================================\n")
cat("  STEP 7 of 7: Economic Analysis\n")
cat("==============================================================================\n\n")

cat("Generating comprehensive policy comparison analysis...\n\n")

step7_start <- Sys.time()

tryCatch({
  source("scripts/08 economic analysis.R", local = FALSE)

  step7_time <- difftime(Sys.time(), step7_start, units = "mins")
  cat(sprintf("\n✓ Step 7 completed in %.1f minutes\n", step7_time))

  if (!file.exists("output/analysis/economic_analysis.pdf")) {
    warning("Expected output file not found: output/analysis/economic_analysis.pdf")
  } else {
    file_size <- file.info("output/analysis/economic_analysis.pdf")$size / 1024^2
    cat(sprintf("Output PDF created: %.1f MB\n", file_size))
  }

}, error = function(e) {
  cat("\n✗ ERROR in Step 7:\n")
  cat("  ", conditionMessage(e), "\n\n")
  stop("Pipeline halted at Step 7")
})

# ==============================================================================
# Pipeline Complete
# ==============================================================================

total_time <- difftime(Sys.time(), pipeline_start, units = "mins")

cat("\n")
cat("==============================================================================\n")
cat("                      PIPELINE COMPLETE!\n")
cat("==============================================================================\n\n")
cat(sprintf("Total execution time: %.1f minutes (%.2f hours)\n\n",
            total_time, total_time / 60))

cat("Outputs created:\n")
cat("  1. data/intermediate/h1b_fy21_24_cleaned.csv\n")
cat("  2. data/processed/h1b_fy21_24_with_pumas.csv\n")
cat("  3. data/processed/h1b_with_percentiles_and_native_comps.csv\n")
cat("  4. output/tables/occ_model_coefficients.csv\n")
cat("  5. data/processed/h1b_with_mincer_wages.csv\n")
cat("  6. [Simulation results in console output]\n")
cat("  7. output/analysis/economic_analysis.pdf\n\n")

cat("To re-run Step 6 with different policy scenarios:\n")
cat("  source('scripts/06 nprm_simulation.R')\n\n")

cat("For questions or issues, see README.md or contact connor@ifp.org\n\n")
cat("==============================================================================\n\n")
