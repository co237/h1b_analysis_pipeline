# ==============================================================================
# DOL NPRM Analysis - First-Time Setup Script
# ==============================================================================
#
# This script helps you set up the project for the first time by:
# 1. Checking and installing required R packages
# 2. Creating necessary directory structure
# 3. Validating that required data files are present
# 4. Providing guidance on missing data files
#
# RUN THIS FIRST before running the analysis pipeline!
#
# ==============================================================================

cat("\n")
cat("======================================================================\n")
cat("        DOL NPRM ANALYSIS - FIRST-TIME SETUP\n")
cat("======================================================================\n\n")

# ==============================================================================
# Step 1: Check R Version
# ==============================================================================

cat("--- Step 1: Checking R Version ---\n")
r_version <- getRversion()
cat("R version:", as.character(r_version), "\n")

if (r_version < "4.0.0") {
  warning("This project requires R >= 4.0.0. Please update R.")
  cat("Download from: https://cran.r-project.org/\n\n")
} else {
  cat("✓ R version is compatible\n\n")
}

# ==============================================================================
# Step 2: Install Required Packages
# ==============================================================================

cat("--- Step 2: Checking Required Packages ---\n")

required_packages <- c(
  # Data manipulation
  "dplyr", "tidyr", "readr", "purrr", "stringr",
  # File I/O
  "readxl", "ipumsr",
  # Geocoding and spatial data
  "tidygeocoder", "sf", "tidycensus",
  # String matching
  "fuzzyjoin",
  # Graph / network (used in data cleaning)
  "igraph",
  # Visualization and formatting
  "ggplot2", "scales", "gridExtra", "knitr",
  # Statistics and modeling
  "fixest", "Hmisc", "matrixStats",
  # Tidyverse utilities
  "forcats", "lubridate", "tibble"
)

missing_packages <- character(0)
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    missing_packages <- c(missing_packages, pkg)
  }
}

if (length(missing_packages) > 0) {
  cat("Missing packages found:", paste(missing_packages, collapse = ", "), "\n\n")
  cat("Installing missing packages...\n")

  install.packages(missing_packages, repos = "https://cran.r-project.org")

  cat("\n✓ Package installation complete\n\n")
} else {
  cat("✓ All required packages are installed\n\n")
}

# ==============================================================================
# Step 3: Create Directory Structure
# ==============================================================================

cat("--- Step 3: Creating Directory Structure ---\n")

# Determine project root
project_root <- getwd()
cat("Project root:", project_root, "\n\n")

# Define directories
directories <- c(
  file.path(project_root, "data"),
  file.path(project_root, "data", "raw"),
  file.path(project_root, "data", "raw", "FOIA_Data"),
  file.path(project_root, "data", "raw", "LCA_Data"),
  file.path(project_root, "data", "raw", "OFLC_Wages"),
  file.path(project_root, "data", "raw", "Other_Data"),
  file.path(project_root, "data", "raw", "census_crosswalks"),
  file.path(project_root, "data", "intermediate"),
  file.path(project_root, "data", "intermediate", "dot_matching"),
  file.path(project_root, "data", "processed"),
  file.path(project_root, "output"),
  file.path(project_root, "output", "figures"),
  file.path(project_root, "output", "tables")
)

for (dir in directories) {
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    cat("Created:", dir, "\n")
  }
}

cat("\n✓ Directory structure created\n\n")

# ==============================================================================
# Step 4: Check for Required Data Files
# ==============================================================================

cat("--- Step 4: Checking for Required Data Files ---\n\n")

data_raw <- file.path(project_root, "data", "raw")
other_data_path <- file.path(data_raw, "Other_Data")

# Define required files with their categories
required_files <- list(
  "H-1B FOIA Data" = list(
    files = c(
      file.path(data_raw, "FOIA_Data","TRK_13139_FY2021.csv"),
      file.path(data_raw, "FOIA_Data","TRK_13139_FY2022.csv"),
      file.path(data_raw, "FOIA_Data","TRK_13139_FY2023.csv"),
      file.path(data_raw, "FOIA_Data","TRK_13139_FY2024_single_reg.csv"),
      file.path(data_raw, "FOIA_Data","TRK_13139_FY2024_multi_reg.csv")
    ),
    required = TRUE
  ),
  "LCA Data" = list(
    files = file.path(data_raw, "LCA_Data"),
    check_dir = TRUE,
    required = TRUE
  ),
  "ACS IPUMS Data" = list(
    files = c(
      file.path(data_raw, "usa_00068.xml"),
      file.path(data_raw, "usa_00068.dat.gz")
    ),
    required = TRUE,
    note = "Filename may vary based on your IPUMS extract"
  ),
  "SOC Definitions" = list(
    files = file.path(data_raw, "soc_2018_definitions.xlsx"),
    required = TRUE
  ),
  "Geographic Crosswalks" = list(
    files = c(
      file.path(other_data_path, "ZIP_COUNTY_122024.xlsx"),
      file.path(other_data_path, "ZIP_CBSA_122024.xlsx"),
      file.path(other_data_path, "area_definitions_m2023.xlsx")
    ),
    required = TRUE
  ),
  "Occupation Crosswalks" = list(
    files = c(
      file.path(other_data_path, "soc_2010_to_2018_crosswalk.xlsx"),
      file.path(other_data_path, "DOT_to_ONET_SOC.xlsx")
    ),
    required = TRUE
  ),
  "OFLC Wage Data" = list(
    files = file.path(data_raw, "OFLC_Wages"),
    check_dir = TRUE,
    required = FALSE
  )
)

all_files_present <- TRUE
missing_categories <- list()

for (category in names(required_files)) {
  item <- required_files[[category]]
  files <- item$files
  is_required <- ifelse(is.null(item$required), TRUE, item$required)
  check_dir <- ifelse(is.null(item$check_dir), FALSE, item$check_dir)

  cat("[", category, "]\n", sep = "")

  if (check_dir) {
    # Check if directory exists and has files
    if (dir.exists(files) && length(list.files(files)) > 0) {
      cat("  ✓ Found:", files, "\n")
      cat("    Files:", length(list.files(files)), "\n")
    } else {
      if (is_required) {
        cat("  ✗ MISSING or EMPTY:", files, "\n")
        missing_categories[[category]] <- item
        all_files_present <- FALSE
      } else {
        cat("  ⚠ Optional (not found):", files, "\n")
      }
    }
  } else {
    # Check individual files
    missing_in_category <- character(0)
    for (file in files) {
      if (file.exists(file)) {
        cat("  ✓ Found:", basename(file), "\n")
      } else {
        missing_in_category <- c(missing_in_category, file)
      }
    }

    if (length(missing_in_category) > 0) {
      if (is_required) {
        for (file in missing_in_category) {
          cat("  ✗ MISSING:", basename(file), "\n")
        }
        missing_categories[[category]] <- item
        all_files_present <- FALSE
      } else {
        cat("  ⚠ Optional files missing\n")
      }
    }
  }

  if (!is.null(item$note)) {
    cat("  Note:", item$note, "\n")
  }

  cat("\n")
}

# ==============================================================================
# Step 5: Provide Guidance
# ==============================================================================

cat("======================================================================\n")

if (all_files_present) {
  cat("✓ SETUP COMPLETE!\n")
  cat("======================================================================\n\n")
  cat("All required files are present. You can now run the analysis:\n\n")
  cat("  source('run_pipeline_simple.R')\n\n")
  cat("Or see README.md for more detailed instructions.\n\n")
} else {
  cat("⚠ SETUP INCOMPLETE - Missing Required Data Files\n")
  cat("======================================================================\n\n")
  cat("The following required data files are missing:\n\n")

  for (category in names(missing_categories)) {
    cat("  •", category, "\n")
  }

  cat("\nPlease see DATA_SOURCES.md for detailed instructions on where to\n")
  cat("download each required data file.\n\n")
  cat("Quick link to documentation:\n")
  cat("  cat DATA_SOURCES.md\n\n")
  cat("After obtaining the data files, run this setup script again:\n")
  cat("  source('setup.R')\n\n")
}

cat("======================================================================\n\n")
