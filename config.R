# ============================================================================
# Configuration File for H-1B Wage Premium Analysis Pipeline
# ============================================================================
# This file contains all paths and configuration settings for the analysis
# pipeline. Update these paths to match your local environment.
# ============================================================================

# --- Project Paths ---
# Get the directory where this config file is located
# Use getwd() as the default, which should be the project root when sourcing
project_root <- tryCatch({
  # Try rstudioapi if available and running in RStudio
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable()) {
    dirname(rstudioapi::getActiveDocumentContext()$path)
  } else {
    getwd()
  }
}, error = function(e) {
  # Fallback to current working directory
  getwd()
})

# Main data directories
data_dir <- file.path(project_root, "data")
data_raw <- file.path(data_dir, "raw")
data_intermediate <- file.path(data_dir, "intermediate")
data_processed <- file.path(data_dir, "processed")

# Output directories
output_dir <- file.path(project_root, "output")
output_figures <- file.path(output_dir, "figures")
output_tables <- file.path(output_dir, "tables")

# Scripts directory
scripts_dir <- file.path(project_root, "scripts")

# --- Input Data Files ---
# FOIA H-1B petition data (FY 2021-2024)
foia_files <- c(
  "TRK_13139_FY2021.csv",
  "TRK_13139_FY2022.csv",
  "TRK_13139_FY2023.csv",
  "TRK_13139_FY2024_single_reg.csv",
  "TRK_13139_FY2024_multi_reg.csv"
)

# LCA (Labor Condition Application) data
# You can specify these as quarterly or annual files
lca_data_path <- file.path(data_raw, "LCA_Data")

# ACS (American Community Survey) IPUMS microdata
acs_ddi_file <- file.path(data_raw, "usa_00061.xml")

# SOC code definitions
soc_definitions_file <- file.path(data_raw, "soc_2018_definitions.xlsx")

# Census crosswalk files for ZIP to PUMA mapping
# These will be downloaded automatically by the geocoding script
census_crosswalks_dir <- file.path(data_raw, "census_crosswalks")

# OFLC wage level data
oflc_data_path <- file.path(data_raw, "OFLC_Wages_2024-25")

# HUD ZIP to County crosswalk
hud_zip_county_file <- file.path(data_raw, "ZIP_COUNTY_122024.xlsx")
hud_zip_cbsa_file <- file.path(data_raw, "ZIP_CBSA_122024.xlsx")

# County to MSA crosswalk
county_msa_file <- file.path(data_raw, "area_definitions_m2023.xlsx")

# SOC 2010 to 2018 crosswalk
soc_crosswalk_file <- file.path(data_raw, "soc_2010_to_2018_crosswalk.xlsx")

# DOT to SOC crosswalk
dot_soc_file <- file.path(data_raw, "DOT_to_ONET_SOC.xlsx")

# --- Intermediate Output Files ---
# From Step 1: Data Cleaning
cleaned_h1b_file <- file.path(data_intermediate, "h1b_fy21_24_cleaned.csv")

# From Step 2: Geocoding
h1b_with_pumas_file <- file.path(data_processed, "h1b_fy21_24_with_pumas.csv")

# --- Final Output Files ---
# These will be generated in the output directories

# --- Analysis Parameters ---
# Years to include in analysis
analysis_years <- c(2022, 2023, 2024)  # FY years (correspond to calendar years 2021-2023)

# Age range for analysis
min_age <- 20
max_age <- 65

# Wage thresholds
min_wage <- 0
max_wage_display <- 250000  # For plotting

# Control configurations for wage premium analysis
control_configs <- list(
  age_only = c("YEAR", "age_grp"),
  age_education = c("YEAR", "EDUCD", "age_grp"),
  age_occupation = c("YEAR", "OCCSOC", "age_grp"),
  full = c("YEAR", "EDUCD", "OCCSOC", "age_grp"),
  age_occ_ed_puma = c("YEAR", "EDUCD", "OCCSOC", "age_grp", "PUMA")  # NEW
)

# --- Function to Check Required Files ---
check_required_files <- function() {
  required_files <- list(
    "ACS DDI" = acs_ddi_file,
    "SOC Definitions" = soc_definitions_file,
    "HUD ZIP-County" = hud_zip_county_file,
    "County-MSA" = county_msa_file,
    "SOC Crosswalk" = soc_crosswalk_file,
    "DOT-SOC" = dot_soc_file
  )

  missing <- character(0)
  for (name in names(required_files)) {
    if (!file.exists(required_files[[name]])) {
      missing <- c(missing, paste0("  - ", name, ": ", required_files[[name]]))
    }
  }

  if (length(missing) > 0) {
    warning("Missing required files:\n", paste(missing, collapse = "\n"))
    return(FALSE)
  }

  cat("All required files found.\n")
  return(TRUE)
}

# --- Function to Create Directories ---
create_directories <- function() {
  dirs <- c(data_raw, data_intermediate, data_processed,
            output_figures, output_tables, census_crosswalks_dir,
            lca_data_path, oflc_data_path)

  for (dir in dirs) {
    if (!dir.exists(dir)) {
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
      cat("Created directory:", dir, "\n")
    }
  }
}

# Create directories on load
create_directories()

cat("Configuration loaded successfully.\n")
cat("Project root:", project_root, "\n")
