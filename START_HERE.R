################################################################################
# START HERE - Run this first in every R session
################################################################################
#
# This sets up your environment correctly so all scripts work.
# Just run this entire file, then open and work on any script you want.
#
################################################################################

# Clear environment
rm(list = ls())

# Set working directory to project root
setwd("/Users/violet/Desktop/repos/h1b_analysis_pipeline")

# Load configuration
source("config.R")

# Confirm setup
cat("\n")
cat("========================================\n")
cat("✓ Environment ready!\n")
cat("========================================\n")
cat("Working directory:", getwd(), "\n")
cat("Project root:", project_root, "\n")
cat("\n")
cat("You can now:\n")
cat("1. Open any script in scripts/ folder\n")
cat("2. Run it line by line\n")
cat("3. All paths will work correctly\n")
cat("\n")
cat("Scripts available:\n")
cat("  - scripts/01_data_cleaning.R\n")
cat("  - scripts/02_geocode_to_pumas.R\n")
cat("  - scripts/03_wage_premium_analysis.R\n")
cat("  - scripts/04_export_h1b_comparisons.R\n")
cat("\n")
