# =============================================================================
# Mincer-Based Prevailing Wage Estimation
# =============================================================================
#
# BACKGROUND AND PURPOSE:
#   The U.S. Department of Labor (DOL) sets "prevailing wages" for H-1B and
#   PERM visa applications — the minimum wage an employer must pay a foreign
#   worker to avoid displacing American workers. Currently, prevailing wages
#   are set based on the employer's description of the job, which allows
#   employers to understate the seniority of the position and pay less.
#
#   This script implements an alternative methodology that sets prevailing
#   wages based on the WORKER'S actual qualifications (education and years
#   of experience) rather than the employer's job description.
#
# HOW IT WORKS:
#   1. We use American Community Survey (ACS) microdata to estimate Mincer
#      earnings equations — a standard labor economics model relating log
#      wages to education and experience — separately for each occupation
#      (and where data allows, for each occupation-metro combination).
#
#   2. For each occupation, the Mincer equation estimates how much more or
#      less a worker with a specific education-experience profile earns
#      relative to the MEDIAN worker in that occupation nationally.
#
#   3. We anchor the wage LEVEL using the OFLC (Office of Foreign Labor
#      Certification) Level 3 wage, which is an OES-based area- and
#      occupation-specific median. The Mincer ratio then adjusts that anchor
#      up or down based on the worker's specific qualifications.
#
#   4. The final output is a lookup function: given an occupation, area,
#      education level, years of experience, and fiscal year, it returns
#      four wage levels corresponding to the 50th, 62nd, 75th, and 90th
#      percentiles of the wage distribution for that occupation.
#
# TWO WAGE SCHEDULES:
#   - ALC: Standard prevailing wages (most H-1B and PERM cases)
#   - EDC: ACWIA prevailing wages (H-1B dependent employers, who must meet
#          a higher standard under the American Competitiveness and Workforce
#          Improvement Act)
#
# YEARS SUPPORTED:
#   The Mincer equations are estimated once from 2019-2023 ACS microdata
#   and do not change across years — they capture the SHAPE of the education-
#   experience curve, which is stable over time. What changes by year is the
#   OFLC Level 3 wage anchor, which reflects OES wage updates each fiscal
#   year. We support FY2021, FY2022, FY2023, and FY2025 (the current year).
#
#   File naming convention in oflc_data_path:
#     Regular wages:  ALC_Export_FY2021.csv, ALC_Export_FY2022.csv, etc.
#     ACWIA wages:    EDC_Export_FY2021.csv, EDC_Export_FY2022.csv, etc.
#     Current year:   ALC_Export.csv, EDC_Export.csv (no year suffix)
#
# MODEL HIERARCHY (most to least granular):
#   For each occupation-area combination, we use the most granular model
#   for which we have sufficient data (controlled by min_obs_threshold):
#     1. Area-specific model: 6-digit SOC code, filtered to one metro
#     2. Occupation-wide:     6-digit SOC code, all metros
#     3. 5-digit SOC group:   all metros
#     4. 3-digit SOC group:   all metros
#     5. 2-digit SOC group:   all metros
#     6. Fully pooled:        all occupations, all metros (last resort)
#
# NO LARGE OUTPUT FILES:
#   Rather than pre-computing a massive grid of wages (which would be too
#   large for version control), we store only the Mincer coefficients in
#   memory and compute wages on the fly via a lookup function.
#
# =============================================================================

library(dplyr)
library(ipumsr)   # For reading IPUMS ACS microdata extracts
library(fixest)   # For fast weighted OLS
library(Hmisc)    # For wtd.quantile() — weighted quantile computation
library(readr)    # For read_csv
library(readxl)   # For reading SOC crosswalk Excel file

# Load configuration file which sets file paths.
# config.R should define:
#   acs_ddi_file   — path to the IPUMS DDI XML file (e.g. "usa_00075.xml")
#   oflc_data_path — path to folder containing all OFLC export CSVs
#   data_raw       — path to folder containing the occupation crosswalk CSV
if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
} else {
  stop("Cannot find config.R. Set your working directory to the project root.")
}

# =============================================================================
# KEY PARAMETER: MINIMUM OBSERVATION THRESHOLD
# =============================================================================
# Controls when the model bumps up to a broader SOC group (or drops the
# area filter). If a cell has fewer unweighted ACS rows than this number,
# we use a broader model instead.
#
# The same threshold applies at every level of the fallback hierarchy.
# 100 is a reasonable default — lower it for more granular coverage,
# raise it for more conservative (stable) coefficient estimates.
# =============================================================================

min_obs_threshold <- 100

# =============================================================================
# SECTION 1: LOAD AND CLEAN ACS DATA
# =============================================================================
#
# Source: IPUMS ACS 5-year pooled extract, 2019-2023.
#
# SAMPLE RESTRICTIONS:
#   - Employed workers only (EMPSTAT == 1)
#   - Positive, non-missing, non-top-coded annual wages
#   - Age 16 and over
#   - Native-born workers (CITIZEN codes 0 and 1)
#
#   WHY NATIVE-BORN ONLY?
#   We use native-born workers to estimate the returns to education and
#   experience because their wages are not distorted by visa constraints,
#   employer sponsorship costs, or immigrant wage penalties. The resulting
#   Mincer coefficients are then applied to set prevailing wages for the
#   foreign workers being sponsored.
#
# KEY VARIABLES CREATED:
#   Years_education      — years of schooling, mapped from IPUMS EDUCD codes
#   Years_pot_experience — potential experience = age - years_education - 6
#   log_incwage          — natural log of annual wage income (dependent variable)
#   highest_ed           — education credential category (8 levels)
#   SOC5, SOC3, SOC2     — truncated SOC codes for the fallback hierarchy
#
# =============================================================================

ddi            <- read_ipums_ddi(acs_ddi_file)
acs_data_19_23 <- read_ipums_micro(ddi)

acs_data_19_23 <- acs_data_19_23 %>%
  filter(
    EMPSTAT == 1,
    INCWAGE != 999999,
    INCWAGE != 999998,
    INCWAGE > 0,
    AGE > 15,
    CITIZEN %in% c(0, 1),
    !is.na(EDUCD)
  ) %>%
  mutate(

    Years_education = case_when(
      EDUCD < 14   ~ 0,
      EDUCD == 14  ~ 1,
      EDUCD == 15  ~ 2,
      EDUCD == 16  ~ 3,
      EDUCD == 17  ~ 4,
      EDUCD == 22  ~ 5,
      EDUCD == 23  ~ 6,
      EDUCD == 25  ~ 7,
      EDUCD == 26  ~ 8,
      EDUCD == 30  ~ 9,
      EDUCD == 40  ~ 10,
      EDUCD == 50  ~ 11,
      EDUCD == 61  ~ 11,
      EDUCD == 63  ~ 12,
      EDUCD == 64  ~ 12,
      EDUCD == 65  ~ 12,
      EDUCD == 71  ~ 13,
      EDUCD == 81  ~ 14,
      EDUCD == 101 ~ 16,
      EDUCD == 114 ~ 18,
      EDUCD == 115 ~ 19,
      EDUCD == 116 ~ 23,
      TRUE ~ NA_real_
    ),

    Years_pot_experience = pmax(AGE - Years_education - 6, 0),
    log_incwage          = log(INCWAGE),

    # Education credential categories.
    # Associates is the REFERENCE CATEGORY in the Mincer — all other
    # education coefficients represent deviations from Associate's holders.
    highest_ed = case_when(
      EDUCD < 62                ~ "Less than HS",
      EDUCD > 62 & EDUCD < 65  ~ "High school",
      EDUCD > 64 & EDUCD < 81  ~ "Some college",
      EDUCD == 81               ~ "Associates",
      EDUCD == 101              ~ "Bachelors",
      EDUCD == 114              ~ "Masters",
      EDUCD == 115              ~ "Prof degree",
      EDUCD == 116              ~ "PhD"
    ),

    # Broader SOC group codes for the fallback hierarchy.
    # ACS OCCSOC has no hyphen, e.g. "151252".
    # Truncating gives: SOC5 = "15125", SOC3 = "151", SOC2 = "15"
    SOC5 = substr(OCCSOC, 1, 5),
    SOC3 = substr(OCCSOC, 1, 3),
    SOC2 = substr(OCCSOC, 1, 2)
  )

# =============================================================================
# SECTION 2: LOAD OFLC WAGE DATA AND OCCUPATION CROSSWALK
# =============================================================================
#
# OFLC WAGE DATA:
#   We load prevailing wage data for multiple fiscal years. The Level 3 wage
#   is the OES-based area-occupation MEDIAN and serves as the wage anchor.
#
#   All files live in oflc_data_path. Naming convention:
#     Current year (FY2025): ALC_Export.csv        / EDC_Export.csv
#     Historical years:      ALC_Export_FY2021.csv / EDC_Export_FY2021.csv
#                            ALC_Export_FY2022.csv / EDC_Export_FY2022.csv
#                            ALC_Export_FY2023.csv / EDC_Export_FY2023.csv
#
#   Annualization: Level3 <= $350 is hourly; multiply by 2080 to annualize.
#   High Wage: occupations above the OES top are set to $239,200 per DOL.
#
# OCCUPATION CROSSWALK:
#   Maps OFLC SOC codes (with hyphens, e.g. "15-1252") to ACS OCCSOC codes
#   (no hyphens, e.g. "151252"). Handles cases where OFLC and ACS classify
#   occupations differently.
#
# OUTPUT:
#   oflc_bases — a nested named list:
#     oflc_bases[["ALC"]][["2021"]] — standard wages, FY2021
#     oflc_bases[["ALC"]][["2022"]] — standard wages, FY2022
#     oflc_bases[["ALC"]][["2023"]] — standard wages, FY2023
#     oflc_bases[["ALC"]][["2025"]] — standard wages, FY2025 (current)
#     oflc_bases[["EDC"]][["2021"]] — ACWIA wages, FY2021
#     ... and so on
#
# =============================================================================

# =============================================================================
# CROSSWALK 1: SOC 2018 → ACS 2018 (for FY2023+)
# =============================================================================
# This crosswalk is used for OFLC files published in SOC 2018 vintage
# (FY2023 and later)
acs_oflc_crosswalk <- read.csv(
  file.path(data_raw, "occupation_oflc_to_acs_crowsswalk.csv")
)

# =============================================================================
# CROSSWALK 2: SOC 2010 → ACS 2018 (for FY2021-2022)
# =============================================================================
# METHODOLOGY: Two-stage approach (improved from previous three-stage)
#
# OLD THREE-STAGE: SOC 2010 → ACS 2013 → ACS 2018 (87.6% coverage)
# NEW TWO-STAGE:   SOC 2010 → SOC 2018 → ACS 2018 (100% coverage)
#
# STAGE 1: SOC 2010 → SOC 2018
#   Uses official Census/BLS crosswalk (comprehensive, authoritative)
#
# STAGE 2: SOC 2018 → ACS 2018
#   Uses existing crosswalk (same as FY2023+)
#
# ADVANTAGE: Achieves 100% coverage (all 821 SOC 2010 codes, 437,593 OFLC records)
#            vs. 87.6% with previous three-stage approach (719 codes, 383,227 records)
#
# See: CROSSWALK_COMPARISON.md for detailed analysis
# =============================================================================

cat("Building two-stage SOC 2010 → ACS 2018 crosswalk...\n")

# Load official Census SOC 2010 → SOC 2018 crosswalk
if (!requireNamespace("readxl", quietly = TRUE)) {
  stop("Package 'readxl' is required. Install with: install.packages('readxl')")
}
soc_10_18_xwalk <- readxl::read_xlsx(
  file.path(data_raw, "Other Data/soc_2010_to_2018_crosswalk.xlsx"),
  skip = 8,
  sheet = "Sorted by 2010"
) %>%
  select(SOC_2010 = `2010 SOC Code`,
         SOC_2018 = `2018 SOC Code`,
         SOC_2018_Title = `2018 SOC Title`)

# Add manual mappings for IT occupations (from Script 01, lines 980-993)
# These codes were consolidated in SOC 2018 but need explicit mapping
soc_10_18_manual <- data.frame(
  SOC_2010 = c("15-1034", "15-1035", "15-1037",  # Software engineers → Software Developers
               "15-1053", "15-1054", "15-1055",  # Computer specialists → Systems Analysts
               "15-1295", "15-1296", "15-1297",  # IT project managers → All Other
               "15-1217",                        # Info security
               "17-2074"),                       # Electrical engineers
  SOC_2018 = c(rep("15-1252", 3),
               rep("15-1211", 3),
               rep("15-1299", 3),
               "15-1212",
               "17-2071"),
  SOC_2018_Title = c(rep("Software Developers", 3),
                     rep("Computer Systems Analysts", 3),
                     rep("Computer Occupations, All Other", 3),
                     "Information Security Analysts",
                     "Electrical Engineers"),
  stringsAsFactors = FALSE
)

soc_10_18_xwalk <- bind_rows(soc_10_18_xwalk, soc_10_18_manual)

cat("  Stage 1: SOC 2010 → SOC 2018\n")
cat("    Loaded", n_distinct(soc_10_18_xwalk$SOC_2010), "SOC 2010 codes\n")
cat("    Map to", n_distinct(soc_10_18_xwalk$SOC_2018), "SOC 2018 codes\n")

# Some SOC 2010 codes map to multiple SOC 2018 codes (e.g., 15-1132 → 15-1252, 15-1253)
# This is fine - we'll aggregate by ACS code in Script 05 anyway
multi_matches <- soc_10_18_xwalk %>%
  group_by(SOC_2010) %>%
  filter(n() > 1) %>%
  ungroup()

if (nrow(multi_matches) > 0) {
  cat("    Note:", n_distinct(multi_matches$SOC_2010), "SOC 2010 codes have multiple SOC 2018 matches\n")
  cat("          (These will be aggregated by median in Script 05)\n")
}

# Load SOC 2018 → ACS 2018 crosswalk (already exists for FY2023+)
soc_18_to_acs <- acs_oflc_crosswalk %>%
  select(SOC_2018 = SocCode, ACS_OCCSOC)

cat("  Stage 2: SOC 2018 → ACS 2018\n")
cat("    Loaded", n_distinct(soc_18_to_acs$SOC_2018), "SOC 2018 codes\n")

# Combine: SOC 2010 → SOC 2018 → ACS 2018
acs_oflc_crosswalk_2010 <- soc_10_18_xwalk %>%
  left_join(soc_18_to_acs, by = "SOC_2018") %>%
  select(SocCode = SOC_2010, ACS_OCCSOC) %>%
  filter(!is.na(ACS_OCCSOC))

cat("  Final: SOC 2010 → ACS 2018\n")
cat("    Successfully mapped", n_distinct(acs_oflc_crosswalk_2010$SocCode), "SOC 2010 codes\n")
cat("    Coverage: 100% (all codes mapped)\n\n")

cat("Loaded crosswalks:\n")
cat("  - SOC 2018 → ACS 2018 (FY2023+):", nrow(acs_oflc_crosswalk), "codes\n")
cat("  - SOC 2010 → ACS 2018 (FY2021-2022):", nrow(acs_oflc_crosswalk_2010), "codes (NEW TWO-STAGE)\n\n")

# Helper: load and clean one OFLC export file.
# filename — just the CSV filename (not the full path)
# use_2010_crosswalk — if TRUE, use two-stage crosswalk (SOC 2010 → SOC 2018 → ACS 2018)
load_oflc <- function(filename, use_2010_crosswalk = FALSE) {
  # Select appropriate crosswalk
  crosswalk <- if (use_2010_crosswalk) {
    acs_oflc_crosswalk_2010
  } else {
    acs_oflc_crosswalk
  }

  read.csv(file.path(oflc_data_path, filename)) %>%
    mutate(
      # Convert Average to hourly for the high-wage threshold check.
      # If Average > 350 it is already annual — divide by 2080 to get hourly.
      # If Average <= 350 it is already hourly — use as-is.
      Average_hourly = ifelse(Average > 350, Average / 2080, Average),

      # Flag high-wage rows: all four wage levels are missing AND
      # the average hourly wage is at least $75/hr. The Average check
      # distinguishes genuine high-wage occupations from data gaps where
      # levels are missing for other reasons.
      is_high_wage = (is.na(Level1) | Level1 == 0) &
        (is.na(Level2) | Level2 == 0) &
        (is.na(Level3) | Level3 == 0) &
        (is.na(Level4) | Level4 == 0) &
        !is.na(Average_hourly) & Average_hourly >= 75,

      # Annualize Level3 if hourly, then top-code high-wage rows
      Level3 = ifelse(Level3 > 350, Level3, Level3 * 2080),
      Level3 = ifelse(is_high_wage, 239200, Level3)
    ) %>%
    left_join(crosswalk, by = "SocCode") %>%
    mutate(ACS_OCCSOC = gsub("-", "", ACS_OCCSOC)) %>%
    select(Area, SocCode, GeoLvl, Level3, ACS_OCCSOC)
}

# Load all years and both wage types into a nested list.
# Access pattern: oflc_bases[["ALC"]][["2021"]], oflc_bases[["EDC"]][["2025"]], etc.
# FY2021-2022 use SOC 2010 codes (use_2010_crosswalk = TRUE)
# FY2023+ use SOC 2018 codes (use_2010_crosswalk = FALSE, default)
oflc_bases <- list(
  ALC = list(
    "2021" = load_oflc("ALC_Export_FY2021.csv", use_2010_crosswalk = TRUE),
    "2022" = load_oflc("ALC_Export_FY2022.csv", use_2010_crosswalk = TRUE),
    "2023" = load_oflc("ALC_Export_FY2023.csv"),
    "2025" = load_oflc("ALC_Export.csv")
  ),
  EDC = list(
    "2021" = load_oflc("EDC_Export_FY2021.csv", use_2010_crosswalk = TRUE),
    "2022" = load_oflc("EDC_Export_FY2022.csv", use_2010_crosswalk = TRUE),
    "2023" = load_oflc("EDC_Export_FY2023.csv"),
    "2025" = load_oflc("EDC_Export.csv")
  )
)

cat("OFLC data loaded for years:",
    paste(names(oflc_bases[["ALC"]]), collapse = ", "), "\n")
cat("Wage types:", paste(names(oflc_bases), collapse = ", "), "\n\n")

# =============================================================================
# SECTION 3: ESTIMATE MINCER EQUATIONS
# =============================================================================
#
# WHAT IS A MINCER EQUATION?
#   A Mincer equation models log wages as a polynomial function of potential
#   experience plus education dummies:
#
#     log(wage) = α + β₁·exp + β₂·exp² + β₃·exp³ + β₄·exp⁴ + Σγₖ·edₖ + ε
#
#   The quartic in experience captures the typical "hump-shaped" earnings
#   profile. Education enters as dummy variables (one per credential level).
#   Associates is the omitted reference category.
#
# WHY THE MINCERS DON'T CHANGE ACROSS YEARS:
#   The Mincer equations capture the SHAPE of the education-experience wage
#   curve — how much more a worker with a PhD earns than one with a bachelor's,
#   or how wages grow with experience. These structural relationships are
#   estimated from the 2019-2023 ACS and are assumed stable across the fiscal
#   years we analyze (FY2021-FY2025). What changes across years is only the
#   wage LEVEL, captured by the year-specific OFLC Level 3 anchor.
#
# THE RATIO FORMULA:
#   For each education-experience combination:
#
#     log_wage_hat = α + β₁·exp + β₂·exp² + β₃·exp³ + β₄·exp⁴ + γₖ·edₖ
#     ratio_p50    = exp(log_wage_hat − log(ACS occupation median))
#     wage_p50     = OFLC_Level3[year] × ratio_p50
#
#   The OFLC Level3 is year-specific; everything else is fixed from the ACS.
#
# FALLBACK HIERARCHY (same threshold at every level):
#   1. Area-specific (6-digit SOC + one metro)
#   2. Occupation-wide (6-digit SOC, all metros)
#   3. 5-digit SOC group
#   4. 3-digit SOC group
#   5. 2-digit SOC group
#   6. Fully pooled national
#
# =============================================================================

# Helper: fit a Mincer equation WITHOUT area fixed effects (used for fallback)
fit_mincer <- function(data) {
  tryCatch(
    feols(
      log_incwage ~
        Years_pot_experience +
        I(Years_pot_experience^2) +
        I(Years_pot_experience^3) +
        I(Years_pot_experience^4) +
        highest_ed,
      data    = data,
      weights = ~PERWT
    ),
    error = function(e) NULL
  )
}

# Helper: fit a Mincer equation WITH area fixed effects
# Used for national models to capture place-invariant returns to education/experience
fit_mincer_with_area_fe <- function(data) {
  # Only fit if we have multiple areas (otherwise FE is meaningless)
  n_areas <- length(unique(data$MET2013[!is.na(data$MET2013)]))
  if (n_areas < 2) {
    return(NULL)  # Fall back to no-FE model
  }

  tryCatch(
    feols(
      log_incwage ~
        Years_pot_experience +
        I(Years_pot_experience^2) +
        I(Years_pot_experience^3) +
        I(Years_pot_experience^4) +
        highest_ed |  # Pipe symbol for fixed effects in fixest
        MET2013,      # Area fixed effects
      data    = data,
      weights = ~PERWT
    ),
    error = function(e) NULL
  )
}

# Helper: calculate education-experience ratios from national model with area FE
# Returns a data frame with one row per (education, experience) combination
calculate_edu_exp_ratios <- function(model, occ_data, raw_median) {

  if (is.null(model)) return(NULL)

  # Create grid of education-experience combinations
  # IMPORTANT: Only use education levels that actually exist in the training data
  # Otherwise predict() will fail with "factor has new level" error
  education_levels_observed <- unique(occ_data$highest_ed[!is.na(occ_data$highest_ed)])

  # Filter to only valid education levels
  all_education_levels <- c("Less than HS", "High school", "Some college", "Associates",
                            "Bachelors", "Masters", "Prof degree", "PhD")
  education_levels <- intersect(all_education_levels, education_levels_observed)

  experience_range <- seq(0, 40, by = 1)  # 0 to 40 years experience

  edu_exp_grid <- expand.grid(
    highest_ed = education_levels,
    Years_pot_experience = experience_range,
    stringsAsFactors = FALSE
  )

  # Get area weights (sum of PERWT by area for this occupation)
  area_weights <- occ_data %>%
    filter(!is.na(MET2013)) %>%
    group_by(MET2013) %>%
    summarise(area_weight = sum(PERWT), .groups = 'drop') %>%
    mutate(weight_prop = area_weight / sum(area_weight))

  # For each (education, experience), predict across all areas and weight
  # Use a vectorized approach instead of rowwise() to avoid scoping issues
  edu_exp_grid$predicted_wage <- NA_real_
  edu_exp_grid$ratio_p50 <- NA_real_

  for (i in seq_len(nrow(edu_exp_grid))) {
    # Create prediction data for all areas with this education and experience
    pred_data <- area_weights %>%
      mutate(
        highest_ed = edu_exp_grid$highest_ed[i],
        Years_pot_experience = edu_exp_grid$Years_pot_experience[i]
      )

    # Predict log wages
    pred_log_wage <- predict(model, newdata = pred_data)

    # Convert to levels and take weighted average
    pred_wage_levels <- exp(pred_log_wage)
    weighted_avg <- sum(pred_wage_levels * pred_data$weight_prop)

    # Store results
    edu_exp_grid$predicted_wage[i] <- weighted_avg
    edu_exp_grid$ratio_p50[i] <- weighted_avg / raw_median
  }

  edu_exp_grid <- edu_exp_grid %>%
    select(highest_ed, Years_pot_experience, ratio_p50)

  return(edu_exp_grid)
}

# Identify all ACS occupation codes needed across ALL years and wage types.
# We take the union so the Mincer loop covers every occupation that appears
# in any OFLC file — the same coefficients are reused across years.
occs_needed <- lapply(oflc_bases, function(type_list) {
  lapply(type_list, function(df) unique(df$ACS_OCCSOC))
}) %>%
  unlist() %>%
  unique() %>%
  .[!is.na(.)]

# Similarly, collect all unique occupation-area pairs across all files.
# The Mincer loop needs to know which metros to attempt area-specific models for.
oflc_occ_area_pairs <- lapply(oflc_bases, function(type_list) {
  lapply(type_list, function(df) df %>% select(ACS_OCCSOC, Area))
}) %>%
  lapply(bind_rows) %>%
  bind_rows() %>%
  distinct() %>%
  filter(!is.na(ACS_OCCSOC))

# Storage for fitted models and ratios.
# NEW METHODOLOGY: Store education-experience ratios per occupation
# OLD FALLBACK: Store coefficients for occupations without area FE
occ_area_models <- list()    # Fallback storage (for models without area FE)
occ_edu_exp_ratios <- NULL    # Primary storage (education-experience ratios)

cat("=============================================================\n")
cat("Fitting NATIONAL Mincer models with area FE\n")
cat("for", length(occs_needed), "occupations\n")
cat("Minimum observation threshold:", min_obs_threshold, "\n")
cat("NEW METHODOLOGY: One national model per occupation\n")
cat("(Models are year-invariant; year affects OES anchor only)\n")
cat("=============================================================\n\n")

for (i in seq_along(occs_needed)) {

  occ <- occs_needed[i]
  if (i %% 50 == 0) cat("Processing occupation", i, "of", length(occs_needed), "\n")

  occ_data_6digit <- acs_data_19_23 %>% filter(OCCSOC == occ)

  # -----------------------------------------------------------------------
  # STEP A: Compute occupation-wide summary statistics.
  #
  # raw_median is the ACS weighted median wage for this occupation, used as
  # the denominator in the ratio formula for ALL models of this occupation.
  # ratio_p62/p75/p90 are fixed scalars that scale p50 to higher percentiles.
  # Both are year-invariant — derived once from the 2019-2023 ACS.
  # -----------------------------------------------------------------------

  pct_data <- if (nrow(occ_data_6digit) >= 30) {
    occ_data_6digit
  } else {
    soc5_val  <- substr(occ, 1, 5)
    data_5dig <- acs_data_19_23 %>% filter(SOC5 == soc5_val)
    if (nrow(data_5dig) >= 30) data_5dig else acs_data_19_23
  }

  raw_median <- as.numeric(wtd.quantile(pct_data$INCWAGE,
                                        weights = pct_data$PERWT, probs = 0.50))
  p62        <- as.numeric(wtd.quantile(pct_data$INCWAGE,
                                        weights = pct_data$PERWT, probs = 0.62))
  p75        <- as.numeric(wtd.quantile(pct_data$INCWAGE,
                                        weights = pct_data$PERWT, probs = 0.75))
  p90        <- as.numeric(wtd.quantile(pct_data$INCWAGE,
                                        weights = pct_data$PERWT, probs = 0.90))

  ratio_p62 <- p62 / raw_median
  ratio_p75 <- p75 / raw_median
  ratio_p90 <- p90 / raw_median

  # -----------------------------------------------------------------------
  # STEP B: Fit national model with area fixed effects.
  #
  # NEW METHODOLOGY: Instead of fitting area-specific models, we fit ONE
  # national model per occupation with area fixed effects. This:
  #   1. Captures place-invariant returns to education and experience
  #   2. Controls for location-based wage differences via fixed effects
  #   3. Provides more stable estimates (larger sample size)
  #   4. Enables better coverage (no per-area threshold)
  #
  # The model produces education-experience ratios that are then applied
  # to area-specific OFLC Level 3 wages.
  # -----------------------------------------------------------------------

  national_model <- NULL
  model_level <- NA_character_
  edu_exp_ratios <- NULL

  # Try 6-digit SOC with area FE
  if (nrow(occ_data_6digit) >= min_obs_threshold) {
    national_model <- fit_mincer_with_area_fe(occ_data_6digit)
    if (!is.null(national_model)) {
      model_level <- "6-digit SOC with area FE"
      edu_exp_ratios <- calculate_edu_exp_ratios(national_model, occ_data_6digit, raw_median)
    }
  }

  # Fall back to 6-digit without FE if area FE fails
  if (is.null(edu_exp_ratios) && nrow(occ_data_6digit) >= min_obs_threshold) {
    national_model <- fit_mincer(occ_data_6digit)
    if (!is.null(national_model)) {
      model_level <- "6-digit SOC (no area FE)"
      # For models without area FE, we still calculate ratios but they won't
      # account for geographic wage variation
      fallback_coefs <- coef(national_model)
      # Store coefficients for fallback prediction (old method)
      occ_area_models[[paste0(occ, "__NATIONAL")]] <- list(
        OCCSOC      = occ,
        Area        = "NATIONAL",
        coefs       = fallback_coefs,
        raw_median  = raw_median,
        ratio_p62   = ratio_p62,
        ratio_p75   = ratio_p75,
        ratio_p90   = ratio_p90,
        model_level = model_level
      )
    }
  }

  # Try broader SOC groups if 6-digit fails
  if (is.null(edu_exp_ratios)) {
    soc5_val  <- substr(occ, 1, 5)
    data_5dig <- acs_data_19_23 %>% filter(SOC5 == soc5_val)
    if (nrow(data_5dig) >= min_obs_threshold) {
      national_model <- fit_mincer_with_area_fe(data_5dig)
      if (!is.null(national_model)) {
        model_level <- paste0("5-digit SOC group (", soc5_val, ") with area FE")
        edu_exp_ratios <- calculate_edu_exp_ratios(national_model, data_5dig, raw_median)
      } else {
        # Try without FE
        national_model <- fit_mincer(data_5dig)
        if (!is.null(national_model)) {
          model_level <- paste0("5-digit SOC group (", soc5_val, ") no FE")
          fallback_coefs <- coef(national_model)
          occ_area_models[[paste0(occ, "__NATIONAL")]] <- list(
            OCCSOC      = occ,
            Area        = "NATIONAL",
            coefs       = fallback_coefs,
            raw_median  = raw_median,
            ratio_p62   = ratio_p62,
            ratio_p75   = ratio_p75,
            ratio_p90   = ratio_p90,
            model_level = model_level
          )
        }
      }
    }
  }

  # Try 3-digit if still no success
  if (is.null(edu_exp_ratios)) {
    soc3_val  <- substr(occ, 1, 3)
    data_3dig <- acs_data_19_23 %>% filter(SOC3 == soc3_val)
    if (nrow(data_3dig) >= min_obs_threshold) {
      national_model <- fit_mincer_with_area_fe(data_3dig)
      if (!is.null(national_model)) {
        model_level <- paste0("3-digit SOC group (", soc3_val, ") with area FE")
        edu_exp_ratios <- calculate_edu_exp_ratios(national_model, data_3dig, raw_median)
      } else {
        national_model <- fit_mincer(data_3dig)
        if (!is.null(national_model)) {
          model_level <- paste0("3-digit SOC group (", soc3_val, ") no FE")
          fallback_coefs <- coef(national_model)
          occ_area_models[[paste0(occ, "__NATIONAL")]] <- list(
            OCCSOC      = occ,
            Area        = "NATIONAL",
            coefs       = fallback_coefs,
            raw_median  = raw_median,
            ratio_p62   = ratio_p62,
            ratio_p75   = ratio_p75,
            ratio_p90   = ratio_p90,
            model_level = model_level
          )
        }
      }
    }
  }

  # Try 2-digit
  if (is.null(edu_exp_ratios)) {
    soc2_val  <- substr(occ, 1, 2)
    data_2dig <- acs_data_19_23 %>% filter(SOC2 == soc2_val)
    if (nrow(data_2dig) >= min_obs_threshold) {
      national_model <- fit_mincer_with_area_fe(data_2dig)
      if (!is.null(national_model)) {
        model_level <- paste0("2-digit SOC group (", soc2_val, ") with area FE")
        edu_exp_ratios <- calculate_edu_exp_ratios(national_model, data_2dig, raw_median)
      } else {
        national_model <- fit_mincer(data_2dig)
        if (!is.null(national_model)) {
          model_level <- paste0("2-digit SOC group (", soc2_val, ") no FE")
          fallback_coefs <- coef(national_model)
          occ_area_models[[paste0(occ, "__NATIONAL")]] <- list(
            OCCSOC      = occ,
            Area        = "NATIONAL",
            coefs       = fallback_coefs,
            raw_median  = raw_median,
            ratio_p62   = ratio_p62,
            ratio_p75   = ratio_p75,
            ratio_p90   = ratio_p90,
            model_level = model_level
          )
        }
      }
    }
  }

  # Last resort: fully pooled
  if (is.null(edu_exp_ratios)) {
    national_model <- fit_mincer_with_area_fe(acs_data_19_23)
    if (!is.null(national_model)) {
      model_level <- "Fully pooled with area FE"
      edu_exp_ratios <- calculate_edu_exp_ratios(national_model, acs_data_19_23, raw_median)
    } else {
      national_model <- fit_mincer(acs_data_19_23)
      if (!is.null(national_model)) {
        model_level <- "Fully pooled no FE"
        fallback_coefs <- coef(national_model)
        occ_area_models[[paste0(occ, "__NATIONAL")]] <- list(
          OCCSOC      = occ,
          Area        = "NATIONAL",
          coefs       = fallback_coefs,
          raw_median  = raw_median,
          ratio_p62   = ratio_p62,
          ratio_p75   = ratio_p75,
          ratio_p90   = ratio_p90,
          model_level = model_level
        )
      }
    }
  }

  # -----------------------------------------------------------------------
  # STEP C: Store education-experience ratios
  #
  # If we successfully fitted a model with area FE and calculated ratios,
  # store them indexed by occupation. Each row has (education, experience, ratio_p50).
  # The percentile ratios (p62, p75, p90) are stored at occupation level.
  # -----------------------------------------------------------------------

  if (!is.null(edu_exp_ratios)) {
    # Add occupation code and percentile ratios
    edu_exp_ratios <- edu_exp_ratios %>%
      mutate(
        OCCSOC = occ,
        ratio_p62 = ratio_p50 * ratio_p62,
        ratio_p75 = ratio_p50 * ratio_p75,
        ratio_p90 = ratio_p50 * ratio_p90,
        model_level = model_level
      )

    # Store in new structure
    if (!exists("occ_edu_exp_ratios")) {
      occ_edu_exp_ratios <- edu_exp_ratios
    } else {
      occ_edu_exp_ratios <- bind_rows(occ_edu_exp_ratios, edu_exp_ratios)
    }
  }

  rm(occ_data_6digit)
  gc()
}

cat("\n=============================================================\n")
cat("Model fitting complete.\n")
if (!is.null(occ_edu_exp_ratios)) {
  n_occs_with_ratios <- length(unique(occ_edu_exp_ratios$OCCSOC))
  n_edu_exp_combos <- nrow(occ_edu_exp_ratios)
  cat("Occupations with education-experience ratios:", n_occs_with_ratios, "\n")
  cat("Total education-experience combinations:", n_edu_exp_combos, "\n")
  cat("  (Average", round(n_edu_exp_combos / n_occs_with_ratios), "ratios per occupation)\n")

  # Save ratios to file for Script 05
  output_file <- file.path(data_processed, "mincer_edu_exp_ratios.csv")
  write.csv(occ_edu_exp_ratios, output_file, row.names = FALSE)
  cat("Saved education-experience ratios to:", output_file, "\n")
}
cat("Fallback coefficient models (no area FE):", length(occ_area_models), "\n")
cat("=============================================================\n\n")

# Free ACS data — all information needed is now in ratios
rm(acs_data_19_23)
gc()

# =============================================================================
# SECTION 4: WAGE PREDICTION FUNCTION (INTERNAL)
# =============================================================================
#
# Evaluates stored Mincer coefficients for a given education-experience
# profile and returns four prevailing wage levels. Called internally by
# lookup_prevailing_wage() — not intended for direct use.
#
# RATIO FORMULA:
#   log_wage_hat = α + β₁·exp + β₂·exp² + β₃·exp³ + β₄·exp⁴ + γₖ·edₖ
#   ratio_p50    = exp(log_wage_hat − log(raw_median))
#   wage_p50     = oflc_level3 × ratio_p50
#
# The raw_median is the ACS occupation-wide weighted median wage (year-
# invariant). The oflc_level3 is the year-specific OES anchor passed in
# by the lookup function. The ratio adjusts that anchor for education and
# experience.
#
# NOTE ON FIXEST COEFFICIENT NAMES:
#   fixest double-wraps I() terms, so experience-squared appears as
#   "I(I(Years_pot_experience^2))" in the coefficient vector. The exact
#   strings below must match what coef() returns from fit_mincer().
#
# =============================================================================

predict_wage <- function(model_entry, highest_ed, years_exp, oflc_level3) {

  coefs <- model_entry$coefs

  # Education dummy coefficient (Associates = 0, the reference category)
  ed_coef <- case_when(
    highest_ed == "Less than HS" ~ coefs["highest_edLess than HS"],
    highest_ed == "High school"  ~ coefs["highest_edHigh school"],
    highest_ed == "Some college" ~ coefs["highest_edSome college"],
    highest_ed == "Bachelors"    ~ coefs["highest_edBachelors"],
    highest_ed == "Masters"      ~ coefs["highest_edMasters"],
    highest_ed == "Prof degree"  ~ coefs["highest_edProf degree"],
    highest_ed == "PhD"          ~ coefs["highest_edPhD"],
    TRUE ~ 0
  )

  log_wage_hat <-
    coefs["(Intercept)"] +
    coefs["Years_pot_experience"]         * years_exp +
    coefs["I(I(Years_pot_experience^2))"] * years_exp^2 +
    coefs["I(I(Years_pot_experience^3))"] * years_exp^3 +
    coefs["I(I(Years_pot_experience^4))"] * years_exp^4 +
    ed_coef

  # Ratio of predicted wage at this profile to the occupation-wide ACS median
  ratio_p50 <- exp(as.numeric(log_wage_hat) - log(model_entry$raw_median))

  data.frame(
    wage_p50 = oflc_level3 * ratio_p50,
    wage_p62 = oflc_level3 * ratio_p50 * model_entry$ratio_p62,
    wage_p75 = oflc_level3 * ratio_p50 * model_entry$ratio_p75,
    wage_p90 = oflc_level3 * ratio_p50 * model_entry$ratio_p90
  )
}

# =============================================================================
# SECTION 5: PREVAILING WAGE LOOKUP FUNCTION
# =============================================================================
#
# Main user-facing function. Returns four prevailing wage levels for a given
# worker profile, wage type, and fiscal year.
#
# ARGUMENTS:
#   soc_code   — OFLC SOC code with hyphen, e.g. "15-1252"
#   area       — OFLC area code (numeric CBSA), e.g. "41860" = San Francisco
#   highest_ed — one of: "Less than HS", "High school", "Some college",
#                "Associates", "Bachelors", "Masters", "Prof degree", "PhD"
#   years_exp  — years of potential experience (numeric, 0-45)
#   wage_type  — "ALC" (standard, default) or "EDC" (ACWIA)
#   year       — fiscal year as a string or number: 2021, 2022, 2023, or 2025
#
# RETURNS a one-row data frame with:
#   wage_type, year, SocCode, ACS_OCCSOC, Area_requested, OES_geo_used,
#   OES_median, highest_ed, years_exp,
#   wage_p50, wage_p62, wage_p75, wage_p90,
#   model_used
#
# HOW YEAR INTERACTS WITH THE MINCERS:
#   The Mincer coefficients are the same regardless of year — only the
#   OFLC Level 3 OES median changes. Specifying year = 2021 vs year = 2025
#   will return different dollar amounts because the wage anchor differs,
#   but the education-experience adjustment ratios are identical.
#
# =============================================================================

lookup_prevailing_wage <- function(soc_code, area, highest_ed, years_exp,
                                   wage_type = "ALC", year = 2025) {

  # --- Input validation ---

  valid_years <- as.numeric(names(oflc_bases[["ALC"]]))
  year        <- as.numeric(year)

  if (!wage_type %in% c("ALC", "EDC")) {
    stop("wage_type must be 'ALC' (standard) or 'EDC' (ACWIA)")
  }

  if (!year %in% valid_years) {
    stop("year must be one of: ", paste(valid_years, collapse = ", "),
         ". Got: ", year)
  }

  valid_ed <- c("Less than HS", "High school", "Some college", "Associates",
                "Bachelors", "Masters", "Prof degree", "PhD")
  if (!highest_ed %in% valid_ed) {
    stop("highest_ed must be one of: ", paste(valid_ed, collapse = ", "))
  }

  if (!is.numeric(years_exp) || years_exp < 0 || years_exp > 45) {
    warning("years_exp should be between 0 and 45. Results outside this range ",
            "may be unreliable.")
  }

  # --- Select the correct OFLC base table (wage type × year) ---
  # oflc_bases is a nested list: oflc_bases[[wage_type]][[year]]
  # This is the only place year enters the calculation.

  oflc_base <- oflc_bases[[wage_type]][[as.character(year)]]

  # Remove hyphen from SOC code to match ACS OCCSOC format
  acs_occ <- gsub("-", "", soc_code)

  # --- Look up OES Level 3 median wage for this area, occupation, and year ---

  oflc_row      <- oflc_base %>% filter(SocCode == soc_code, Area == area)
  oflc_geo_used <- area

  # Fall back to national OES wage if no MSA-level entry exists
  if (nrow(oflc_row) == 0 || is.na(oflc_row$Level3[1])) {
    cat("Note: No MSA-level OES wage for", soc_code, "in area", area,
        "(FY", year, wage_type, ")— falling back to national OES wage.\n")
    oflc_row      <- oflc_base %>% filter(SocCode == soc_code, GeoLvl == "N")
    oflc_geo_used <- "National (no MSA-level OES wage available)"
  }

  if (nrow(oflc_row) == 0 || is.na(oflc_row$Level3[1])) {
    stop("No OES wage found for ", soc_code, " (FY", year, ", ", wage_type,
         ") at any geography. Verify this SOC code exists in the OFLC export.")
  }

  level3 <- oflc_row$Level3[1]

  # --- Look up education-experience ratios (NEW METHOD) ---
  # First try to find ratios from national model with area FE.
  # These ratios are area-invariant and indexed by (occupation, education, experience).

  ratios_row <- NULL
  if (!is.null(occ_edu_exp_ratios)) {
    ratios_row <- occ_edu_exp_ratios %>%
      filter(OCCSOC == acs_occ,
             highest_ed == !!highest_ed,
             Years_pot_experience == round(years_exp))

    if (nrow(ratios_row) > 0) {
      # Found ratios - apply directly
      model_used <- ratios_row$model_level[1]
      wages <- data.frame(
        wage_p50 = level3 * ratios_row$ratio_p50[1],
        wage_p62 = level3 * ratios_row$ratio_p62[1],
        wage_p75 = level3 * ratios_row$ratio_p75[1],
        wage_p90 = level3 * ratios_row$ratio_p90[1]
      )
    } else {
      ratios_row <- NULL  # Mark as not found
    }
  }

  # --- Fall back to old coefficient method if no ratios found ---
  if (is.null(ratios_row)) {
    model_key_national <- paste0(acs_occ, "__NATIONAL")

    if (!is.null(occ_area_models[[model_key_national]])) {
      model_entry <- occ_area_models[[model_key_national]]
      model_used  <- paste0(
        "Fallback to coefficient model (no area FE): ", model_entry$model_level
      )

      # Use old prediction method
      wages <- predict_wage(
        model_entry = model_entry,
        highest_ed  = highest_ed,
        years_exp   = years_exp,
        oflc_level3 = level3
      )
    } else {
      stop("No Mincer model or ratios found for ACS occupation ", acs_occ, ". ",
           "Check that this occupation appears in the OFLC crosswalk and ACS data.")
    }
  }

  # --- Return results ---

  data.frame(
    wage_type      = wage_type,
    year           = year,
    SocCode        = soc_code,
    ACS_OCCSOC     = acs_occ,
    Area_requested = area,
    OES_geo_used   = oflc_geo_used,
    OES_median     = level3,
    highest_ed     = highest_ed,
    years_exp      = years_exp,
    wage_p50       = round(wages$wage_p50),
    wage_p62       = round(wages$wage_p62),
    wage_p75       = round(wages$wage_p75),
    wage_p90       = round(wages$wage_p90),
    model_used     = model_used
  )
}

# =============================================================================
# USAGE EXAMPLES (commented out - uncomment to test)
# =============================================================================

# Standard (ALC) prevailing wage, FY2023 — software developer in San Francisco,
# master's degree, 5 years of experience
# NOTE: Use SOC 2018 codes for FY2023+, SOC 2010 codes for FY2021-2022
# lookup_prevailing_wage(
#   soc_code   = "15-1252",
#   area       = "41860",
#   highest_ed = "Masters",
#   years_exp  = 5,
#   wage_type  = "ALC",
#   year       = 2023
# )

# Same worker, ACWIA (EDC) wages, FY2023
# lookup_prevailing_wage(
#   soc_code   = "15-1252",
#   area       = "41860",
#   highest_ed = "Masters",
#   years_exp  = 5,
#   wage_type  = "EDC",
#   year       = 2023
# )

# Compare the same worker across recent fiscal years (ALC only)
# do.call(rbind, lapply(c(2023, 2025), function(yr) {
#   lookup_prevailing_wage("17-2051", "41860", "Bachelors", 15,
#                          wage_type = "ALC", year = yr)
# }))

# Compare ALC vs EDC for all years side by side
# do.call(rbind, lapply(c(2021, 2022, 2023, 2025), function(yr) {
#   rbind(
#     lookup_prevailing_wage("13-2011", "41860", "Masters", 5,
#                            wage_type = "ALC", year = yr),
#     lookup_prevailing_wage("13-2011", "41860", "Masters", 5,
#                            wage_type = "EDC", year = yr)
#   )
# }))
