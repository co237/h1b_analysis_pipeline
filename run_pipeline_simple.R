# ==============================================================================
# H-1B Wage Premium Analysis Pipeline - SIMPLIFIED VERSION
# ==============================================================================
#
# This runs the analysis in clear, manageable steps with checkpoints.
# If a step crashes, you don't lose progress - just run this again.
#
# ==============================================================================

cat("\n")
cat("======================================================================\n")
cat("        H-1B WAGE PREMIUM ANALYSIS - SIMPLIFIED PIPELINE\n")
cat("======================================================================\n\n")

# Check if we're in the right directory
if (!file.exists("config.R")) {
  cat("ERROR: Cannot find config.R in current directory\n")
  cat("Current directory:", getwd(), "\n\n")
  cat("Please set your working directory to the project root:\n")
  cat("  Option 1: Open dol-nprm-analysis.Rproj in RStudio (recommended)\n")
  cat("  Option 2: In RStudio: Session > Set Working Directory > To Project Directory\n")
  cat("  Option 3: Use setwd('path/to/dol-nprm-analysis')\n\n")
  stop("Wrong working directory")
}

cat("Working directory:", getwd(), "\n\n")

# Load configuration
source("config.R")

# Track timing
pipeline_start <- Sys.time()

# ==============================================================================
# Configuration
# ==============================================================================

# Which steps to run?
run_steps <- list(
  step1 = TRUE,   # Process LCA data
  step2 = TRUE,   # Process FOIA data
  step3 = TRUE,   # Merge FOIA + LCA (using original script for now)
  geocode = TRUE, # Geocode to PUMAs
  analyze = TRUE, # Wage premium analysis
  export = TRUE   # Export H-1B with native comparisons
)

# Skip steps that are already complete?
skip_completed <- TRUE

cat("Pipeline Configuration:\n")
cat("  Step 1 (LCA):        ", ifelse(run_steps$step1, "ENABLED", "SKIPPED"), "\n")
cat("  Step 2 (FOIA):       ", ifelse(run_steps$step2, "ENABLED", "SKIPPED"), "\n")
cat("  Step 3 (Merge):      ", ifelse(run_steps$step3, "ENABLED", "SKIPPED"), "\n")
cat("  Geocoding:           ", ifelse(run_steps$geocode, "ENABLED", "SKIPPED"), "\n")
cat("  Analysis:            ", ifelse(run_steps$analyze, "ENABLED", "SKIPPED"), "\n")
cat("  Export comparisons:  ", ifelse(run_steps$export, "ENABLED", "SKIPPED"), "\n")
cat("  Skip completed:      ", skip_completed, "\n")
cat("\n")

# ==============================================================================
# Pre-Flight Check
# ==============================================================================

cat("--- Pre-Flight Check ---\n")

# Check for required directories
required_dirs <- c(lca_data_path, foia_data_path, data_intermediate, data_processed)
dirs_ok <- TRUE

for (dir_path in required_dirs) {
  if (!dir.exists(dir_path)) {
    cat("  ✗ Missing:", dir_path, "\n")
    dirs_ok <- FALSE
  }
}

if (!dirs_ok) {
  stop("\nMissing required directories. Please check data setup.")
}

cat("✓ Required directories found\n\n")

# ==============================================================================
# STEP 1: Process LCA Data
# ==============================================================================

if (run_steps$step1) {
  checkpoint <- file.path(data_intermediate, "step1_lca_processed.RData")

  if (skip_completed && file.exists(checkpoint)) {
    cat("=== STEP 1: Process LCA Data ===\n")
    cat("✓ Already completed (checkpoint exists)\n")
    cat("  ", checkpoint, "\n\n")
  } else {
    step1_start <- Sys.time()

    cat("\n")
    cat("======================================================================\n")
    cat("  RUNNING STEP 1: Process LCA Data\n")
    cat("======================================================================\n")

    tryCatch({
      source(file.path("scripts", "simple", "step1_process_lca.R"), local = FALSE)

      step1_time <- difftime(Sys.time(), step1_start, units = "mins")
      cat(sprintf("\n✓ Step 1 completed in %.1f minutes\n", step1_time))

      # Memory cleanup between steps (keep essential variables)
      keep_vars <- c("pipeline_start", "run_steps", "skip_completed",
                     "data_intermediate", "data_processed", "data_raw",
                     "foia_data_path", "lca_data_path", "output_figures", "output_tables")
      rm(list = ls()[!ls() %in% keep_vars])
      gc(verbose = FALSE)

    }, error = function(e) {
      cat("\n✗ ERROR in Step 1:\n")
      cat("  ", conditionMessage(e), "\n\n")
      cat("You can try running Step 1 individually:\n")
      cat("  source('scripts/simple/step1_process_lca.R')\n\n")
      stop("Pipeline halted at Step 1")
    })
  }
}

# ==============================================================================
# STEP 2: Process FOIA Data
# ==============================================================================

if (run_steps$step2) {
  # Reload config in case variables were cleared
  if (!exists("data_intermediate")) source("config.R")

  checkpoint <- file.path(data_intermediate, "step2_foia_processed.RData")

  if (skip_completed && file.exists(checkpoint)) {
    cat("=== STEP 2: Process FOIA Data ===\n")
    cat("✓ Already completed (checkpoint exists)\n")
    cat("  ", checkpoint, "\n\n")
  } else {
    step2_start <- Sys.time()

    cat("\n")
    cat("======================================================================\n")
    cat("  RUNNING STEP 2: Process FOIA Data\n")
    cat("======================================================================\n")

    tryCatch({
      source(file.path("scripts", "simple", "step2_process_foia.R"), local = FALSE)

      step2_time <- difftime(Sys.time(), step2_start, units = "mins")
      cat(sprintf("\n✓ Step 2 completed in %.1f minutes\n", step2_time))

      # Memory cleanup (keep essential variables)
      keep_vars <- c("pipeline_start", "run_steps", "skip_completed",
                     "data_intermediate", "data_processed", "data_raw",
                     "foia_data_path", "lca_data_path", "output_figures", "output_tables",
                     "scripts_dir")
      rm(list = ls()[!ls() %in% keep_vars])
      gc(verbose = FALSE)

    }, error = function(e) {
      cat("\n✗ ERROR in Step 2:\n")
      cat("  ", conditionMessage(e), "\n\n")
      cat("You can try running Step 2 individually:\n")
      cat("  source('scripts/simple/step2_process_foia.R')\n\n")
      stop("Pipeline halted at Step 2")
    })
  }
}

# ==============================================================================
# STEP 3: Merge and Clean (Original Script)
# ==============================================================================

if (run_steps$step3) {
  # Reload config in case variables were cleared
  if (!exists("data_intermediate")) source("config.R")

  checkpoint <- file.path(data_intermediate, "h1b_fy21_24_cleaned.csv")

  if (skip_completed && file.exists(checkpoint)) {
    cat("=== STEP 3: Merge FOIA + LCA & Clean ===\n")
    cat("✓ Already completed (checkpoint exists)\n")
    cat("  ", checkpoint, "\n\n")
  } else {
    cat("\n")
    cat("======================================================================\n")
    cat("  RUNNING STEP 3: Merge & Clean Data\n")
    cat("======================================================================\n")
    cat("\nNOTE: This uses the original data cleaning script.\n")
    cat("This step takes ~15-20 minutes and uses the most memory.\n")
    cat("If it crashes, try:\n")
    cat("  1. Close other applications\n")
    cat("  2. Restart R\n")
    cat("  3. Run: source('scripts/01_data_cleaning.R')\n\n")

    step3_start <- Sys.time()

    tryCatch({
      source(file.path("scripts", "01_data_cleaning.R"), local = FALSE)

      step3_time <- difftime(Sys.time(), step3_start, units = "mins")
      cat(sprintf("\n✓ Step 3 completed in %.1f minutes\n", step3_time))

      # Memory cleanup (keep essential variables)
      keep_vars <- c("pipeline_start", "run_steps", "skip_completed",
                     "data_intermediate", "data_processed", "data_raw",
                     "foia_data_path", "lca_data_path", "output_figures", "output_tables",
                     "scripts_dir")
      rm(list = ls()[!ls() %in% keep_vars])
      gc(verbose = FALSE)

    }, error = function(e) {
      cat("\n✗ ERROR in Step 3:\n")
      cat("  ", conditionMessage(e), "\n\n")
      cat("This step is memory-intensive. Try:\n")
      cat("  1. Close other applications\n")
      cat("  2. Restart R: .rs.restartR()\n")
      cat("  3. Run individually: source('scripts/01_data_cleaning.R')\n\n")
      stop("Pipeline halted at Step 3")
    })
  }
}

# ==============================================================================
# STEP 4: Geocode to PUMAs
# ==============================================================================

if (run_steps$geocode) {
  # Reload config in case variables were cleared
  if (!exists("data_processed")) source("config.R")

  checkpoint <- file.path(data_processed, "h1b_fy21_24_with_pumas.csv")

  if (skip_completed && file.exists(checkpoint)) {
    cat("=== STEP 4: Geocode to PUMAs ===\n")
    cat("✓ Already completed (checkpoint exists)\n")
    cat("  ", checkpoint, "\n\n")
  } else {
    step4_start <- Sys.time()

    cat("\n")
    cat("======================================================================\n")
    cat("  RUNNING STEP 4: Geocode to PUMAs\n")
    cat("======================================================================\n")

    tryCatch({
      source(file.path("scripts", "02_geocode_to_pumas.R"), local = FALSE)

      step4_time <- difftime(Sys.time(), step4_start, units = "mins")
      cat(sprintf("\n✓ Step 4 completed in %.1f minutes\n", step4_time))

      # Memory cleanup (keep essential variables)
      keep_vars <- c("pipeline_start", "run_steps", "skip_completed",
                     "data_intermediate", "data_processed", "data_raw",
                     "foia_data_path", "lca_data_path", "output_figures", "output_tables",
                     "scripts_dir")
      rm(list = ls()[!ls() %in% keep_vars])
      gc(verbose = FALSE)

    }, error = function(e) {
      cat("\n✗ ERROR in Step 4:\n")
      cat("  ", conditionMessage(e), "\n\n")
      stop("Pipeline halted at Step 4")
    })
  }
}

# ==============================================================================
# STEP 5: Wage Premium Analysis
# ==============================================================================

if (run_steps$analyze) {
  step5_start <- Sys.time()

  cat("\n")
  cat("======================================================================\n")
  cat("  RUNNING STEP 5: Wage Premium Analysis\n")
  cat("======================================================================\n")

  tryCatch({
    source(file.path("scripts", "03_wage_premium_analysis.R"), local = FALSE)

    step5_time <- difftime(Sys.time(), step5_start, units = "mins")
    cat(sprintf("\n✓ Step 5 completed in %.1f minutes\n", step5_time))

  }, error = function(e) {
    cat("\n✗ ERROR in Step 5:\n")
    cat("  ", conditionMessage(e), "\n\n")
    stop("Pipeline halted at Step 5")
  })
}

# ==============================================================================
# STEP 6: Export H-1B with Native Comparisons
# ==============================================================================

if (run_steps$export) {
  step6_start <- Sys.time()

  cat("\n")
  cat("======================================================================\n")
  cat("  RUNNING STEP 6: Export H-1B with Native Comparisons\n")
  cat("======================================================================\n")

  tryCatch({
    source(file.path("scripts", "04_export_h1b_comparisons.R"), local = FALSE)

    step6_time <- difftime(Sys.time(), step6_start, units = "mins")
    cat(sprintf("\n✓ Step 6 completed in %.1f minutes\n", step6_time))

  }, error = function(e) {
    cat("\n✗ ERROR in Step 6:\n")
    cat("  ", conditionMessage(e), "\n\n")
    stop("Pipeline halted at Step 6")
  })
}

# ==============================================================================
# Pipeline Complete
# ==============================================================================

total_time <- difftime(Sys.time(), pipeline_start, units = "mins")

cat("\n")
cat("======================================================================\n")
cat("                   PIPELINE COMPLETE!\n")
cat("======================================================================\n\n")
cat(sprintf("Total execution time: %.1f minutes\n\n", total_time))

cat("Outputs:\n")
cat("  - Cleaned data:    ", data_intermediate, "\n")
cat("  - Processed data:  ", data_processed, "\n")
cat("  - Figures:         ", output_figures, "\n")
cat("  - Tables:          ", output_tables, "\n")
cat("\n")
cat("Check pipeline status:\n")
cat("  source('check_pipeline_status.R')\n\n")
