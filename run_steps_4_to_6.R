# Run Steps 4-6 only (skipping Steps 1-3 which have existing outputs)

cat("\n")
cat("==============================================================================\n")
cat("         DOL NPRM ANALYSIS - STEPS 4-6 ONLY\n")
cat("==============================================================================\n\n")

pipeline_start <- Sys.time()

# Check working directory
if (!file.exists("config.R")) {
  stop("ERROR: Cannot find config.R. Set working directory to project root.")
}

cat("Working directory:", getwd(), "\n")
cat("Start time:", format(pipeline_start, "%Y-%m-%d %H:%M:%S"), "\n\n")

# Verify prerequisite files exist
cat("Checking prerequisite files...\n")
prereqs <- c(
  "data/intermediate/h1b_fy21_24_cleaned.csv",
  "data/processed/h1b_fy21_24_with_pumas.csv",
  "data/processed/h1b_with_percentiles_and_native_comps.csv"
)
for (f in prereqs) {
  if (!file.exists(f)) {
    stop(paste("Missing prerequisite:", f))
  }
  cat("  OK:", f, "\n")
}
cat("\n")

# ==============================================================================
# STEP 4: Calculate Mincer Prevailing Wages
# ==============================================================================

cat("\n")
cat("==============================================================================\n")
cat("  STEP 4 of 6: Calculate Mincer Prevailing Wages\n")
cat("==============================================================================\n\n")

step4_start <- Sys.time()

tryCatch({
  source("scripts/04 Calculate new prevailing wages.R", local = FALSE)

  step4_time <- difftime(Sys.time(), step4_start, units = "mins")
  cat(sprintf("\n Step 4 completed in %.1f minutes\n", step4_time))

  if (!exists("occ_edu_exp_ratios") || !exists("oflc_bases")) {
    stop("Step 4 did not create required objects: occ_edu_exp_ratios, oflc_bases")
  }
  cat("Mincer education-experience ratios and OFLC data loaded in memory\n")

}, error = function(e) {
  cat("\n ERROR in Step 4:\n")
  cat("  ", conditionMessage(e), "\n\n")
  stop("Pipeline halted at Step 4")
})

# Do NOT run gc() here - we need to preserve the model objects in memory

# ==============================================================================
# STEP 5: Apply Mincer Wages to H-1B Petitions
# ==============================================================================

cat("\n")
cat("==============================================================================\n")
cat("  STEP 5 of 6: Apply Mincer Wages to H-1B Petitions\n")
cat("==============================================================================\n\n")

step5_start <- Sys.time()

tryCatch({
  source("scripts/05 Apply new PWs to H1B petitions.R", local = FALSE)

  step5_time <- difftime(Sys.time(), step5_start, units = "mins")
  cat(sprintf("\n Step 5 completed in %.1f minutes\n", step5_time))

  if (!file.exists("data/processed/h1b_with_mincer_wages.csv")) {
    warning("Expected output file not found: data/processed/h1b_with_mincer_wages.csv")
  } else {
    file_size <- file.info("data/processed/h1b_with_mincer_wages.csv")$size / 1024^2
    cat(sprintf("Output file created: %.1f MB\n", file_size))
  }

}, error = function(e) {
  cat("\n ERROR in Step 5:\n")
  cat("  ", conditionMessage(e), "\n\n")
  stop("Pipeline halted at Step 5")
})

gc(verbose = FALSE)

# ==============================================================================
# STEP 6: NPRM Simulation
# ==============================================================================

cat("\n")
cat("==============================================================================\n")
cat("  STEP 6 of 6: NPRM Simulation\n")
cat("==============================================================================\n\n")

step6_start <- Sys.time()

tryCatch({
  source("scripts/06 nprm_simulation.R", local = FALSE)

  step6_time <- difftime(Sys.time(), step6_start, units = "mins")
  cat(sprintf("\n Step 6 completed in %.1f minutes\n", step6_time))

}, error = function(e) {
  cat("\n ERROR in Step 6:\n")
  cat("  ", conditionMessage(e), "\n\n")
  stop("Pipeline halted at Step 6")
})

# ==============================================================================
# Pipeline Complete
# ==============================================================================

total_time <- difftime(Sys.time(), pipeline_start, units = "mins")

cat("\n")
cat("==============================================================================\n")
cat("                      STEPS 4-6 COMPLETE!\n")
cat("==============================================================================\n\n")
cat(sprintf("Total execution time: %.1f minutes (%.2f hours)\n\n",
            total_time, total_time / 60))
cat("==============================================================================\n\n")
