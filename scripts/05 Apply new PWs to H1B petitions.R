# =============================================================================
# Tag H-1B Petitions with Mincer-Based Prevailing Wages
# =============================================================================
#
# PURPOSE:
#   For each H-1B petition, calculate four prevailing wage levels (50th, 62nd,
#   75th, and 90th percentiles) based on:
#     1. OFLC Level 3 wage for the occupation and area
#     2. Mincer equation adjustments for education and experience
#
# PREREQUISITES:
#   Script 04 must have been run in the same session so that the following
#   objects are available in memory:
#     - occ_area_models  — list of fitted Mincer models by occupation and area
#     - oflc_bases       — nested list of OFLC wage tables by type and year
#     - predict_wage()   — wage prediction function
#
# INPUT:
#   data/processed/h1b_with_percentiles_and_native_comps.csv
#     - Contains H-1B petitions with ACS_OCCSOC codes (from Script 03)
#     - ACS_OCCSOC codes have hyphens and may use "YY" wildcards
#
# OUTPUT:
#   data/processed/h1b_with_mincer_wages.csv
#     - Same petitions with four new columns: pw_p50, pw_p62, pw_p75, pw_p90
#     - Success rate: ~71% of petitions get valid wages
#     - Remaining ~29% get NA (missing education, MSA, or no matching OFLC/Mincer data)
#
# CRITICAL FIXES IMPLEMENTED:
#   1. HYPHEN STRIPPING: H-1B data has "17-21YY", OFLC has "1721XX"
#      → Strip hyphens from H-1B ACS_OCCSOC before joining
#
#   2. WILDCARD NORMALIZATION: H-1B uses "YY", OFLC uses "XX"
#      → Convert all "YY" → "XX" for consistent matching
#      (Original crosswalk from Script 03 uses "YY" for some occupation groups,
#       FY2021-2022 crosswalk uses "XX" for all groups)
#
#   3. OFLC DEDUPLICATION: Multiple SOC codes map to same ACS code
#      → Aggregate OFLC wages by (ACS_OCCSOC, MSA, Year) using median
#      (Example: SOC 17-2111, 17-2112, 17-2151 all → ACS "1721XX")
#      → Prevents many-to-many joins that would create duplicate petition rows
#
#   4. SOC_CODE FALLBACK: Petitions have both SOC_CODE and SOC_CODE_2010
#      → Try SOC_CODE (2018) first, fall back to SOC_CODE_2010 if missing
#
# For detailed explanation of the entire wage calculation process, see:
#   MINCER_WAGE_CALCULATION_EXPLAINED.md
#
# =============================================================================

# Load configuration
if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
} else {
  stop("Cannot find config.R. Set your working directory to the project root.")
}

# Check if prerequisites are available (either in memory or as files)
# NEW METHODOLOGY: We need education-experience ratios (not coefficients)
if (!exists("occ_edu_exp_ratios") && !file.exists(file.path(data_processed, "mincer_edu_exp_ratios.csv"))) {
  cat("Mincer ratios not found in memory or file. Running Script 04 first...\n\n")
  # Save current working directory
  original_wd <- getwd()
  # Source from project root, not from scripts directory
  script_04_path <- if (file.exists("scripts/04 Calculate new prevailing wages.R")) {
    "scripts/04 Calculate new prevailing wages.R"
  } else if (file.exists("04 Calculate new prevailing wages.R")) {
    "04 Calculate new prevailing wages.R"
  } else {
    stop("Cannot find Script 04")
  }
  source(script_04_path, local = FALSE)
  # Restore working directory
  setwd(original_wd)
  cat("\nScript 04 complete. Continuing with Script 05...\n\n")
}

# Load ratios from file if not in memory
if (!exists("occ_edu_exp_ratios") || is.null(occ_edu_exp_ratios)) {
  cat("Loading education-experience ratios from file...\n")
  occ_edu_exp_ratios <- read.csv(file.path(data_processed, "mincer_edu_exp_ratios.csv"))
  cat("Loaded ratios for", length(unique(occ_edu_exp_ratios$OCCSOC)), "occupations\n\n")
}

# Load OFLC bases if not in memory (needed for OFLC Level 3 wages)
if (!exists("oflc_bases")) {
  cat("OFLC data not found in memory. Running Script 04 to load it...\n\n")
  source(ifelse(file.exists("scripts/04 Calculate new prevailing wages.R"),
                "scripts/04 Calculate new prevailing wages.R",
                "04 Calculate new prevailing wages.R"), local = FALSE)
}

# =============================================================================
# STEP 0: LOAD AND PREPARE H-1B DATA
# =============================================================================

h1b_22_24 <- read.csv(file.path(data_processed, "h1b_with_percentiles_and_native_comps.csv"))

h1b_22_24 %>%
  group_by(petition_beneficiary_edu_code) %>%
  summarise(n = n())

h1b_22_24 <- h1b_22_24 %>%
  mutate(
    Years_education = case_when(
      petition_beneficiary_edu_code == "A" ~ 10,   # No diploma
      petition_beneficiary_edu_code == "B" ~ 12,   # High school
      petition_beneficiary_edu_code == "C" ~ 13,   # Some college
      petition_beneficiary_edu_code == "D" ~ 13,   # Some college
      petition_beneficiary_edu_code == "E" ~ 14,   # Associates
      petition_beneficiary_edu_code == "F" ~ 16,   # Bachelors
      petition_beneficiary_edu_code == "G" ~ 18,   # Masters
      petition_beneficiary_edu_code == "H" ~ 19,   # Professional degree
      petition_beneficiary_edu_code == "I" ~ 23,   # Doctorate
      TRUE ~ NA_real_
    ),
    AGE                  = registration_lottery_year - registration_birth_year,
    PW_year              = registration_lottery_year - 1,
    Years_pot_experience = pmax(AGE - Years_education - 6, 0),
    log_incwage          = log(petition_annual_pay_clean),

    highest_ed = case_when(
      petition_beneficiary_edu_code == "A"             ~ "Less than HS",
      petition_beneficiary_edu_code == "B"             ~ "High school",
      petition_beneficiary_edu_code %in% c("C", "D")  ~ "Some college",
      petition_beneficiary_edu_code == "E"             ~ "Associates",
      petition_beneficiary_edu_code == "F"             ~ "Bachelors",
      petition_beneficiary_edu_code == "G"             ~ "Masters",
      petition_beneficiary_edu_code == "H"             ~ "Prof degree",
      petition_beneficiary_edu_code == "I"             ~ "PhD"
    ),

    # Try SOC_CODE first (SOC 2018), fall back to SOC_CODE_2010 if missing
    # Both fields already have hyphens (e.g., "15-1252" or "15-1132")
    SocCode_hyphen = ifelse(!is.na(SOC_CODE) & SOC_CODE != "",
                            SOC_CODE,
                            SOC_CODE_2010),
    SocCode_source = ifelse(!is.na(SOC_CODE) & SOC_CODE != "",
                            "SOC_2018",
                            "SOC_2010"),

    # Stripped and truncated codes (kept for reference, not used in lookup)
    SocCode = gsub("-", "", SocCode_hyphen),
    SOC5    = substr(SocCode, 1, 5),
    SOC3    = substr(SocCode, 1, 3),
    SOC2    = substr(SocCode, 1, 2),

    # =========================================================================
    # CRITICAL FIX 1: STRIP HYPHENS FROM ACS_OCCSOC
    # =========================================================================
    #
    # PROBLEM:
    #   - H-1B data (from Script 03) has ACS_OCCSOC WITH HYPHENS: "17-21YY"
    #   - OFLC data (from Script 04) has ACS_OCCSOC WITHOUT HYPHENS: "1721XX"
    #   - Join by ACS_OCCSOC would fail: "17-21YY" ≠ "1721XX"
    #
    # WHY THIS HAPPENED:
    #   Script 03 uses original crosswalk which preserves hyphens
    #   Script 04's load_oflc() function strips hyphens (line 281)
    #
    # FIX:
    #   Strip hyphens from H-1B ACS_OCCSOC before joining
    #   "17-21YY" → "1721YY"
    #
    ACS_OCCSOC = gsub("-", "", ACS_OCCSOC),

    # =========================================================================
    # CRITICAL FIX 2: NORMALIZE WILDCARD CHARACTERS
    # =========================================================================
    #
    # PROBLEM:
    #   - Original crosswalk (Script 03) uses "YY" wildcards: "1721YY", "1940YY"
    #   - FY2021-2022 crosswalk (Script 04) uses "XX" wildcards: "1721XX", "1940XX"
    #   - Even after stripping hyphens, "1721YY" ≠ "1721XX" → join fails
    #
    # WHY THIS HAPPENED:
    #   The original OFLC→ACS crosswalk file uses mixed wildcard conventions:
    #     - "XX" for most occupation groups (e.g., "11-10XX", "13-20XX")
    #     - "YY" for some groups (e.g., "17-21YY", "19-40YY")
    #   The three-stage FY2021-2022 crosswalk standardized everything to "XX"
    #   for consistency with ACS vintage mappings.
    #
    # FIX:
    #   Standardize all "YY" → "XX" in H-1B data before joining
    #   "1721YY" → "1721XX"
    #
    # IMPACT:
    #   Before: 7,408 petitions with "1721YY" got NA wages
    #   After:  These petitions successfully match OFLC "1721XX" data
    #   Overall improvement: +4,531 petitions with valid wages
    #
    ACS_OCCSOC = gsub("YY$", "XX", ACS_OCCSOC)
    #
    # =========================================================================
  )

# =============================================================================
# STEP 1: IDENTIFY UNIQUE LOOKUP COMBINATIONS
# =============================================================================
#
# Rows missing any of SOC code, MSA code, education, experience, or year
# cannot be looked up and will receive NA wages via the left join in Step 3.
#
# NOTE: We use ACS_OCCSOC for matching because OFLC data has been crosswalked
# to ACS codes. This handles both SOC 2018 and SOC 2010 vintages correctly.
#
# =============================================================================

unique_combos <- h1b_22_24 %>%
  filter(
    !is.na(ACS_OCCSOC),
    !is.na(MSA_code),
    !is.na(highest_ed),
    !is.na(Years_pot_experience),
    !is.na(PW_year)
  ) %>%
  mutate(MSA_code = as.character(MSA_code)) %>%
  distinct(ACS_OCCSOC, MSA_code, highest_ed, Years_pot_experience, PW_year)

cat("Total H-1B petitions:", nrow(h1b_22_24), "\n")
cat("Unique lookup combinations:", nrow(unique_combos), "\n")
cat("Petitions missing required fields (will receive NA wages):",
    nrow(h1b_22_24) - sum(
      !is.na(h1b_22_24$ACS_OCCSOC) &
        !is.na(h1b_22_24$MSA_code) &
        !is.na(h1b_22_24$highest_ed) &
        !is.na(h1b_22_24$Years_pot_experience) &
        !is.na(h1b_22_24$PW_year)
    ), "\n\n")

# =============================================================================
# STEP 2: VECTORIZED WAGE LOOKUP
# =============================================================================
#
# Three vectorized joins replace the row-by-row loop entirely:
#   2a. Join OFLC Level 3 medians (MSA-level, fall back to national)
#   2b. Join Mincer coefficients (area-specific, fall back to national)
#   2c. Compute all four wage levels in a single mutate()
#
# =============================================================================

# --- 2a. Stack all ALC years and join OES Level 3 medians ---

oflc_alc_all_years <- bind_rows(
  lapply(names(oflc_bases[["ALC"]]), function(yr) {
    oflc_bases[["ALC"]][[yr]] %>% mutate(PW_year = as.integer(yr))
  })
)

# MSA-level wages
# CRITICAL FIX 3: DEDUPLICATE OFLC DATA BEFORE JOINING
#
# PROBLEM:
#   The crosswalk maps multiple detailed SOC codes to aggregated ACS codes.
#   For example, in FY2025 for MSA 1000005:
#     SOC 11-1011 → ACS_OCCSOC "1110XX" → Level3 = $231,483
#     SOC 11-1021 → ACS_OCCSOC "1110XX" → Level3 = $142,480
#     SOC 11-1031 → ACS_OCCSOC "1110XX" → Level3 = $65,247
#
#   If we join H-1B petitions (which use aggregated ACS codes) directly with
#   this OFLC data, one petition with "1110XX" would match ALL THREE rows,
#   creating duplicate petition records in the output.
#
#   Before this fix: 273,546 input petitions → 577,964 output rows (2.1x inflation!)
#   After this fix:  273,546 input petitions → 273,546 output rows (correct)
#
# SOLUTION:
#   Aggregate OFLC data by (ACS_OCCSOC, MSA, Year) and take the MEDIAN Level3
#   wage when multiple SOC codes map to the same ACS code. This gives one
#   representative wage per ACS occupation-area-year combination.
#
# WHY MEDIAN?:
#   Robust to outliers. Some detailed occupations might have extreme wages
#   that would skew a mean.
#
oflc_msa <- oflc_alc_all_years %>%
  filter(!is.na(Level3)) %>%
  select(SocCode, Area, PW_year, Level3, ACS_OCCSOC) %>%
  rename(MSA_code = Area) %>%
  mutate(MSA_code = as.character(MSA_code)) %>%
  group_by(ACS_OCCSOC, MSA_code, PW_year) %>%
  summarise(
    Level3 = median(Level3, na.rm = TRUE),  # Take median across SOC codes
    SocCode = first(SocCode),                # Keep one representative SOC code
    .groups = "drop"
  )

# National fallback wages
# Apply same deduplication logic for national-level wages
oflc_national_oes <- oflc_alc_all_years %>%
  filter(GeoLvl == "N", !is.na(Level3)) %>%
  select(SocCode, PW_year, Level3, ACS_OCCSOC) %>%
  group_by(ACS_OCCSOC, PW_year) %>%
  summarise(
    Level3_national = median(Level3, na.rm = TRUE),
    SocCode_national = first(SocCode),
    .groups = "drop"
  )

# Join MSA-level first, fill gaps with national
# NOTE: Join by ACS_OCCSOC (not SocCode) to handle both SOC 2018 and SOC 2010 vintages
unique_combos <- unique_combos %>%
  left_join(oflc_msa,
            by = c("ACS_OCCSOC", "MSA_code", "PW_year")) %>%
  left_join(oflc_national_oes,
            by = c("ACS_OCCSOC", "PW_year")) %>%
  mutate(
    Level3_used   = ifelse(!is.na(Level3), Level3, Level3_national),
    SocCode_used  = ifelse(!is.na(SocCode), SocCode, SocCode_national),
    oflc_geo_used = ifelse(!is.na(Level3), as.character(MSA_code), "National fallback")
  ) %>%
  select(-Level3, -Level3_national, -SocCode, -SocCode_national)

# --- 2b. Join education-experience ratios (NEW METHODOLOGY) ---
#
# NEW APPROACH:
#   Instead of joining area-specific coefficients and computing wages from
#   scratch, we simply join pre-computed ratios indexed by (occupation,
#   education, experience). These ratios are area-invariant and come from
#   national Mincer models with area fixed effects.
#
#   The area-specific wage information comes entirely from the OFLC Level3
#   wage (already joined above).
#
# ADVANTAGES:
#   - Simpler code (no coefficient arithmetic)
#   - Better coverage (one ratio per occupation, not per area)
#   - More stable estimates (larger sample sizes)
#   - Place-invariant education/experience premiums

# Round experience to nearest integer for matching
unique_combos <- unique_combos %>%
  mutate(Years_pot_experience_rounded = round(Years_pot_experience))

# Join ratios by (occupation, education, rounded experience)
unique_combos <- unique_combos %>%
  left_join(
    occ_edu_exp_ratios %>%
      select(OCCSOC, highest_ed, Years_pot_experience,
             ratio_p50, ratio_p62, ratio_p75, ratio_p90, model_level),
    by = c("ACS_OCCSOC" = "OCCSOC",
           "highest_ed" = "highest_ed",
           "Years_pot_experience_rounded" = "Years_pot_experience")
  )

# --- 2c. Apply ratios to OFLC Level 3 wages ---
# Much simpler than before - just multiply!

unique_combos <- unique_combos %>%
  mutate(
    pw_p50         = round(Level3_used * ratio_p50),
    pw_p62         = round(Level3_used * ratio_p62),
    pw_p75         = round(Level3_used * ratio_p75),
    pw_p90         = round(Level3_used * ratio_p90),
    pw_oflc_median = Level3_used,
    pw_model_used  = model_level
  ) %>%
  select(ACS_OCCSOC, MSA_code, highest_ed, Years_pot_experience, PW_year,
         pw_p50, pw_p62, pw_p75, pw_p90, pw_oflc_median, pw_model_used, SocCode_used)

cat("Wage prediction complete.\n")
cat("Combinations with valid wages:", sum(!is.na(unique_combos$pw_p50)), "\n")
cat("Combinations with NA wages:   ", sum(is.na(unique_combos$pw_p50)), "\n\n")

# =============================================================================
# STEP 3: JOIN WAGE RESULTS BACK TO FULL PETITION DATASET
# =============================================================================

h1b_22_24 <- h1b_22_24 %>%
  mutate(MSA_code = as.character(MSA_code)) %>%
  left_join(
    unique_combos,
    by = c("ACS_OCCSOC", "MSA_code", "highest_ed",
           "Years_pot_experience", "PW_year")
  )

# =============================================================================
# STEP 4: VALIDATION
# =============================================================================

cat("=== Validation ===\n")
cat("Total petitions:", nrow(h1b_22_24), "\n")
cat("Petitions with valid pw_p50:", sum(!is.na(h1b_22_24$pw_p50)), "\n")
cat("Petitions with NA pw_p50:  ", sum(is.na(h1b_22_24$pw_p50)), "\n\n")

# Wage monotonicity check — p50 < p62 < p75 < p90 should always hold
h1b_22_24 %>%
  filter(!is.na(pw_p50)) %>%
  summarise(
    any_p62_below_p50 = any(pw_p62 < pw_p50),
    any_p75_below_p62 = any(pw_p75 < pw_p62),
    any_p90_below_p75 = any(pw_p90 < pw_p75)
  ) %>%
  print()

# Distribution of wages by education level
h1b_22_24 %>%
  filter(!is.na(pw_p50)) %>%
  group_by(highest_ed) %>%
  summarise(
    n          = n(),
    median_p50 = median(pw_p50, na.rm = TRUE),
    median_p75 = median(pw_p75, na.rm = TRUE),
    median_p90 = median(pw_p90, na.rm = TRUE)
  ) %>%
  arrange(median_p50) %>%
  print()

# Distribution of model types used
h1b_22_24 %>%
  filter(!is.na(pw_model_used)) %>%
  mutate(model_type = ifelse(grepl("Area-specific", pw_model_used),
                             "Area-specific", "Occupation-wide fallback")) %>%
  count(model_type) %>%
  print()

# =============================================================================
# STEP 5: SAVE OUTPUT
# =============================================================================

output_file <- file.path(data_processed, "h1b_with_mincer_wages.csv")
write.csv(h1b_22_24, output_file, row.names = FALSE)
cat("\nSaved to:", output_file, "\n")


nrow(h1b_22_24 %>% filter(petition_annual_pay_clean >pw_p50))
nrow(h1b_22_24 %>% filter(petition_annual_pay_clean >pw_p62))
nrow(h1b_22_24 %>% filter(petition_annual_pay_clean >pw_p75))
nrow(h1b_22_24 %>% filter(petition_annual_pay_clean >pw_p90))
nrow(h1b_22_24 %>% filter(!is.na(petition_annual_pay_clean)))

h1b_22_24 %>% filter(petition_annual_pay_clean <pw_p50) %>%
  group_by(wage_level_combined) %>%
  summarise(n = n())

h1b_22_24 %>% filter(petition_annual_pay_clean <pw_p50) %>%
  group_by(PW_WAGE_LEVEL) %>%
  summarise(n = n())
h1b_22_24 %>% filter(petition_annual_pay_clean >pw_p50) %>%
  group_by(PW_WAGE_LEVEL) %>%
  summarise(n = n())

nrow(h1b_22_24 %>% filter(petition_percentile >50 & !is.na(pw_p50)))
nrow(h1b_22_24 %>% filter(petition_percentile >50 & !is.na(pw_p50) & petition_annual_pay_clean < pw_p50))

nrow(h1b_22_24 %>% filter(petition_percentile >75& !is.na(pw_p50)))
nrow(h1b_22_24 %>% filter(petition_percentile >75 & !is.na(pw_p50) & petition_annual_pay_clean <pw_p50))

