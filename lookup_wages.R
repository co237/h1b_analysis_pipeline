# =============================================================================
# Fast Interactive Wage Lookup
# =============================================================================
#
# This script loads pre-computed Mincer ratios and OFLC wage data to provide
# instant prevailing wage queries. NO MODEL FITTING REQUIRED.
#
# PREREQUISITE: Run Script 04 first to generate the data files
#
# USAGE:
#   source("lookup_wages.R")  # Takes ~1-2 seconds
#   result <- get_prevailing_wages("15-1252", "Bachelors", 5, "41860", 2023, "ALC")
#
# =============================================================================

cat("Loading prevailing wage lookup function...\n")

# Load configuration
if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
} else {
  stop("Cannot find config.R. Set your working directory to the project root.")
}

# Load required library
suppressPackageStartupMessages(library(dplyr))

# =============================================================================
# Load pre-computed data files (fast - no model fitting)
# =============================================================================

cat("Loading pre-computed data files...\n")

# Load Mincer ratios (education-experience premiums)
ratios_file <- file.path(data_processed, "mincer_edu_exp_ratios.rds")
if (!file.exists(ratios_file)) {
  stop("Mincer ratios file not found: ", ratios_file,
       "\nPlease run Script 04 first to generate this file.")
}
occ_edu_exp_ratios <- readRDS(ratios_file)
cat("  ✓ Loaded Mincer ratios for", length(unique(occ_edu_exp_ratios$OCCSOC)), "occupations\n")

# Load OFLC wage bases (occupation-specific, area-specific anchors)
oflc_file <- file.path(data_processed, "oflc_bases.rds")
if (!file.exists(oflc_file)) {
  stop("OFLC wage data file not found: ", oflc_file,
       "\nPlease run Script 04 first to generate this file.")
}
oflc_bases <- as.data.frame(readRDS(oflc_file))

# Standardize column names - oflc_bases has SocCode, ACS_OCCSOC, and Area
if ("Area" %in% names(oflc_bases)) {
  names(oflc_bases)[names(oflc_bases) == "Area"] <- "MSA_code"
}

cat("  ✓ Loaded OFLC wage data:", format(nrow(oflc_bases), big.mark=","), "combinations\n")

# Load crosswalks (SOC → ACS mappings)
crosswalk_file <- file.path(data_processed, "crosswalks.rds")
if (!file.exists(crosswalk_file)) {
  stop("Crosswalk file not found: ", crosswalk_file,
       "\nPlease run Script 04 first to generate this file.")
}
crosswalks_list <- readRDS(crosswalk_file)
crosswalk_2018 <- as.data.frame(crosswalks_list$crosswalk_2018)
fy2021_crosswalk <- as.data.frame(crosswalks_list$fy2021_crosswalk)

# Standardize ACS_OCCSOC format (remove hyphens to match Mincer ratios)
crosswalk_2018$ACS_OCCSOC <- gsub("-", "", crosswalk_2018$ACS_OCCSOC)
fy2021_crosswalk$ACS_OCCSOC <- gsub("-", "", fy2021_crosswalk$ACS_OCCSOC)

cat("  ✓ Loaded occupation code crosswalks\n")
cat("    - SOC 2018 → ACS:", nrow(crosswalk_2018), "codes\n")
cat("    - SOC 2010 → ACS:", nrow(fy2021_crosswalk), "codes\n")

cat("Data loaded successfully! Ready for wage queries.\n\n")

# =============================================================================
# Define the wage lookup function
# =============================================================================

#' Get Prevailing Wages for Specific Petition Characteristics
#'
#' Calculates Mincer-based prevailing wages for a given combination of
#' occupation, education, experience, area, and year. Uses pre-computed
#' data for instant results (no model fitting required).
#'
#' @param soc_code Character. SOC occupation code (6-digit, with or without hyphen).
#'        Can be SOC 2010 or SOC 2018 format. Examples: "15-1252", "151252"
#' @param education Character. Education level. One of:
#'        "Less than HS", "High school", "Some college", "Associates",
#'        "Bachelors", "Masters", "Prof degree", "PhD"
#' @param experience Numeric. Years of potential work experience (0-50)
#' @param msa_code Character or numeric. MSA code. Examples: "41860", 41860
#' @param year Numeric. Fiscal year (2021-2026)
#' @param wage_type Character. Either "ALC" (standard) or "EDC" (ACWIA).
#'        Default: "ALC"
#'
#' @return A named list containing:
#'   - status: "success" or "error"
#'   - soc_code: Input SOC code (cleaned)
#'   - acs_occsoc: Mapped ACS occupation code
#'   - education: Input education level
#'   - experience: Input experience (rounded to nearest integer)
#'   - msa_code: Input MSA code
#'   - year: Input year
#'   - wage_type: Input wage type
#'   - oflc_level3: OFLC Level 3 wage (occupational median anchor)
#'   - pw_p50: Mincer wage at 50th percentile (median)
#'   - pw_p62: Mincer wage at 62nd percentile
#'   - pw_p75: Mincer wage at 75th percentile
#'   - pw_p90: Mincer wage at 90th percentile
#'   - ratio_p50, ratio_p62, ratio_p75, ratio_p90: Education-experience ratios
#'   - message: Informative message (if error)
#'
#' @examples
#' # Software Developer, Bachelor's, 5 years, San Francisco, 2023
#' result <- get_prevailing_wages("15-1252", "Bachelors", 5, "41860", 2023, "ALC")
#' result$pw_p50  # Get median wage
#'
#' # Mechanical Engineer, Master's, 10 years, Houston, 2022, ACWIA
#' result <- get_prevailing_wages("17-2141", "Masters", 10, "26420", 2022, "EDC")
#'
get_prevailing_wages <- function(soc_code,
                                  education,
                                  experience,
                                  msa_code,
                                  year,
                                  wage_type = "ALC") {

  # =============================================================================
  # Input validation
  # =============================================================================

  valid_education <- c("Less than HS", "High school", "Some college", "Associates",
                       "Bachelors", "Masters", "Prof degree", "PhD")

  if (!education %in% valid_education) {
    return(list(
      status = "error",
      message = paste0("Invalid education level. Must be one of: ",
                      paste(valid_education, collapse = ", "))
    ))
  }

  if (experience < 0 || experience > 50) {
    return(list(
      status = "error",
      message = "Experience must be between 0 and 50 years"
    ))
  }

  if (!year %in% c(2021, 2022, 2023, 2024, 2025, 2026)) {
    return(list(
      status = "error",
      message = "Year must be 2021-2026"
    ))
  }

  if (!wage_type %in% c("ALC", "EDC")) {
    return(list(
      status = "error",
      message = "wage_type must be 'ALC' (standard) or 'EDC' (ACWIA)"
    ))
  }

  # Clean inputs - standardize to hyphenated format for crosswalk lookup
  soc_input <- as.character(soc_code)
  if (grepl("-", soc_input)) {
    soc_clean <- soc_input  # Already has hyphen
  } else {
    # Add hyphen: "151252" → "15-1252"
    if (nchar(soc_input) == 6) {
      soc_clean <- paste0(substr(soc_input, 1, 2), "-", substr(soc_input, 3, 6))
    } else {
      return(list(
        status = "error",
        message = "SOC code must be 6 digits (e.g., '15-1252' or '151252')"
      ))
    }
  }

  msa_clean <- as.character(msa_code)
  exp_rounded <- round(experience)

  # =============================================================================
  # STEP 1: Map SOC code to ACS_OCCSOC
  # =============================================================================

  # Try SOC 2018 → ACS crosswalk first (for FY2023+)
  acs_match <- crosswalk_2018 %>%
    filter(SocCode == soc_clean) %>%
    pull(ACS_OCCSOC)

  # If not found, try SOC 2010 → ACS crosswalk (for FY2021-2022)
  if (length(acs_match) == 0) {
    acs_match <- fy2021_crosswalk %>%
      filter(SOC_2010_clean == soc_clean) %>%
      pull(ACS_OCCSOC)
  }

  if (length(acs_match) == 0) {
    return(list(
      status = "error",
      message = paste0("SOC code '", soc_clean, "' not found in crosswalks. ",
                      "Check if it's a valid SOC 2010 or SOC 2018 code.")
    ))
  }

  acs_occsoc <- acs_match[1]  # Take first match if multiple

  # =============================================================================
  # STEP 2: Look up OFLC Level 3 wage (using specific SOC code)
  # =============================================================================
  # CRITICAL: Match by SocCode (not ACS_OCCSOC) to get the specific occupation's
  # wage. Multiple SOC codes can map to the same ACS code but have different wages.
  # Example: 11-1011, 11-1021, 11-1031 all map to 1110XX but have different Level3.

  oflc_match <- oflc_bases %>%
    filter(
      SocCode == soc_clean,
      MSA_code == msa_clean,
      PW_year == year,
      wage_type == !!wage_type
    )

  if (nrow(oflc_match) == 0) {
    return(list(
      status = "error",
      message = paste0("No OFLC wage data found for:\n",
                      "  SOC: ", soc_clean, " (ACS: ", acs_occsoc, ")\n",
                      "  MSA: ", msa_clean, "\n",
                      "  Year: ", year, "\n",
                      "  Type: ", wage_type, "\n",
                      "This occupation may not be present in this area.")
    ))
  }

  oflc_level3 <- oflc_match$Level3[1]

  # =============================================================================
  # STEP 3: Look up Mincer ratios
  # =============================================================================

  ratio_match <- occ_edu_exp_ratios %>%
    filter(
      OCCSOC == acs_occsoc,
      highest_ed == education,
      Years_pot_experience == exp_rounded
    )

  if (nrow(ratio_match) == 0) {
    return(list(
      status = "error",
      message = paste0("No Mincer ratios found for:\n",
                      "  Occupation (ACS): ", acs_occsoc, "\n",
                      "  Education: ", education, "\n",
                      "  Experience: ", exp_rounded, " years\n",
                      "This combination may not exist in the ACS data.")
    ))
  }

  ratio_p50 <- ratio_match$ratio_p50[1]
  ratio_p62 <- ratio_match$ratio_p62[1]
  ratio_p75 <- ratio_match$ratio_p75[1]
  ratio_p90 <- ratio_match$ratio_p90[1]

  # =============================================================================
  # STEP 4: Calculate prevailing wages
  # =============================================================================

  pw_p50 <- oflc_level3 * ratio_p50
  pw_p62 <- oflc_level3 * ratio_p62
  pw_p75 <- oflc_level3 * ratio_p75
  pw_p90 <- oflc_level3 * ratio_p90

  # =============================================================================
  # Return results
  # =============================================================================

  return(list(
    status = "success",
    soc_code = soc_clean,
    acs_occsoc = acs_occsoc,
    education = education,
    experience = exp_rounded,
    msa_code = msa_clean,
    year = year,
    wage_type = wage_type,
    oflc_level3 = round(oflc_level3, 2),
    pw_p50 = round(pw_p50, 2),
    pw_p62 = round(pw_p62, 2),
    pw_p75 = round(pw_p75, 2),
    pw_p90 = round(pw_p90, 2),
    ratio_p50 = round(ratio_p50, 4),
    ratio_p62 = round(ratio_p62, 4),
    ratio_p75 = round(ratio_p75, 4),
    ratio_p90 = round(ratio_p90, 4)
  ))
}

# =============================================================================
# Print usage instructions
# =============================================================================

cat("=============================================================\n")
cat("WAGE LOOKUP FUNCTION READY\n")
cat("=============================================================\n")
cat("Usage:\n")
cat("  result <- get_prevailing_wages(soc_code, education, experience,\n")
cat("                                  msa_code, year, wage_type)\n\n")
cat("Example:\n")
cat("  result <- get_prevailing_wages('15-1252', 'Bachelors', 5,\n")
cat("                                  '41860', 2023, 'ALC')\n")
cat("  result$pw_p50  # Get 50th percentile wage\n\n")
cat("Education options:\n")
cat("  'Less than HS', 'High school', 'Some college', 'Associates',\n")
cat("  'Bachelors', 'Masters', 'Prof degree', 'PhD'\n\n")
cat("Wage type: 'ALC' (standard) or 'EDC' (ACWIA)\n")
cat("=============================================================\n\n")
