# =============================================================================
# Tag H-1B Petitions with Mincer-Based Prevailing Wages
# =============================================================================
#
# PURPOSE:
#   For each H-1B petition, calculate four prevailing wage levels (50th, 62nd,
#   75th, and 90th percentiles) by combining:
#     1. Occupation-specific OFLC Level 3 wages (e.g., 17-2171 Petroleum Engineers)
#     2. Aggregated Mincer ratios for education-experience (e.g., 1721XX all engineers)
#
#   This preserves occupation-specific wage differences while applying consistent
#   education-experience adjustments from national Mincer models.
#
# PREREQUISITES:
#   Script 04 must have been run in the same session so that the following
#   objects are available in memory:
#     - occ_edu_exp_ratios — education-experience ratios by occupation
#     - oflc_bases         — nested list of OFLC wage tables by type and year
#
# INPUT:
#   data/processed/h1b_with_percentiles_and_native_comps.csv
#     - Contains H-1B petitions with ACS_OCCSOC codes (from Script 03)
#     - ACS_OCCSOC codes have hyphens and may use "YY" wildcards
#
# OUTPUT:
#   data/processed/h1b_with_mincer_wages.csv
#     - Same petitions with four new columns: pw_p50, pw_p62, pw_p75, pw_p90
#     - Success rate: ~76% of petitions get valid wages (209,129 / 273,546)
#     - Remaining ~24% get NA (primarily due to missing education codes)
#
# KEY IMPLEMENTATION DETAILS:
#   1. SPECIFIC OFLC WAGES: Each SOC code keeps its own OFLC Level 3 wage
#      → 17-2171 Petroleum Engineers ≠ 17-2141 Mechanical Engineers
#
#   2. AGGREGATED MINCER RATIOS: Education-experience premiums are aggregated by ACS code
#      → All 17-21XX engineers share the same ratios (1721YY Mincer model)
#
#   3. SOC 2010→2018 CONVERSION: FY2021-2022 OFLC data converted from 2010 to 2018 format
#      → Multiple 2010 codes (15-1132, 15-1133) → Single 2018 code (15-1252), aggregated
#
#   4. TWO MATCHING KEYS:
#      → SOC_CODE_clean (specific, with XX) matches OFLC wages
#      → ACS_OCCSOC (aggregated, with YY) matches Mincer ratios
#
# For detailed explanation of the methodology, see:
#   MINCER_METHODOLOGY.md
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
ratios_file_rds <- file.path(data_processed, "mincer_edu_exp_ratios.rds")
ratios_file_csv <- file.path(data_processed, "mincer_edu_exp_ratios.csv")

if (!exists("occ_edu_exp_ratios") && !file.exists(ratios_file_rds) && !file.exists(ratios_file_csv)) {
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
  # Prefer RDS (much faster and smaller), fall back to CSV
  if (file.exists(ratios_file_rds)) {
    occ_edu_exp_ratios <- readRDS(ratios_file_rds)
    cat("Loaded from RDS:", ratios_file_rds, "\n")
  } else if (file.exists(ratios_file_csv)) {
    occ_edu_exp_ratios <- read.csv(ratios_file_csv)
    cat("Loaded from CSV:", ratios_file_csv, "\n")
  }
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
    # OLD FIX (NOW REMOVED):
    #   Previously normalized: ACS_OCCSOC = gsub("YY$", "XX", ACS_OCCSOC)
    #
    # NEW APPROACH:
    #   - Keep ACS_OCCSOC with "YY" wildcards (e.g., "1721YY")
    #   - This matches the Mincer ratios file which uses "YY"
    #   - For OFLC matching, use SOC_CODE_clean (created below) with "XX"
    #
    # TWO SEPARATE KEYS:
    #   1. ACS_OCCSOC (with YY) → joins to Mincer education-experience ratios
    #   2. SOC_CODE_clean (with XX) → joins to OFLC specific SOC wages
    #
    # This allows:
    #   - Aggregated Mincer models (1721YY for all engineers)
    #   - Specific OFLC wages (17-2171 for petroleum engineers)
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
  mutate(
    MSA_code = as.character(MSA_code),
    # Strip hyphens and normalize wildcards in SOC_CODE to match OFLC format
    SOC_CODE_clean = as.character(gsub("-", "", SOC_CODE)),
    SOC_CODE_clean = gsub("YY$", "XX", SOC_CODE_clean)
  )

# =============================================================================
# Load SOC 2010→2018 crosswalk (used for OFLC data conversion below)
# =============================================================================
if (!exists("soc_10_18_xwalk")) {
  cat("Loading SOC 2010→2018 crosswalk for OFLC data conversion...\n")
  if (!requireNamespace("readxl", quietly = TRUE)) {
    stop("Package 'readxl' is required. Install with: install.packages('readxl')")
  }
  soc_10_18_xwalk <- readxl::read_xlsx(
    file.path(data_raw, "Other Data/soc_2010_to_2018_crosswalk.xlsx"),
    skip = 8,
    sheet = "Sorted by 2010"
  ) %>%
    select(SOC_2010 = `2010 SOC Code`, SOC_2018 = `2018 SOC Code`)
  cat("Loaded", nrow(soc_10_18_xwalk), "SOC code mappings\n\n")
}

# Create bidirectional lookup tables
soc_18_to_10 <- soc_10_18_xwalk %>%
  mutate(
    SOC_2010_clean = gsub("-", "", SOC_2010),
    SOC_2018_clean = gsub("-", "", SOC_2018)
  ) %>%
  select(SOC_2018_clean, SOC_2010_clean) %>%
  distinct()

unique_combos <- unique_combos %>%
  distinct(SOC_CODE_clean, ACS_OCCSOC, MSA_code, highest_ed, Years_pot_experience, PW_year)

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

cat("DIAGNOSTIC: OFLC data after stacking:\n")
cat("  Total rows:", nrow(oflc_alc_all_years), "\n")
cat("  Rows with NA ACS_OCCSOC:", sum(is.na(oflc_alc_all_years$ACS_OCCSOC)), "\n")
cat("  Unique ACS_OCCSOC codes:", length(unique(oflc_alc_all_years$ACS_OCCSOC)), "\n")
cat("  Sample ACS_OCCSOC values:", paste(head(sort(unique(oflc_alc_all_years$ACS_OCCSOC)), 10), collapse=", "), "\n\n")

# MSA-level wages with 2010→2018 SOC conversion
#
# LOGIC:
#   1. OFLC FY2021/2022 use 2010 SOC codes (e.g., 15-1132, 15-1133)
#   2. Petitions use 2018 SOC codes (e.g., 15-1252)
#   3. Convert OFLC 2010→2018 using crosswalk
#   4. Aggregate when multiple 2010 codes map to one 2018 code
#
#   Example conversion:
#     2010: 15-1132 (Software Developers, Applications) → Level3 = $95K
#     2010: 15-1133 (Software Developers, Systems)      → Level3 = $105K
#     → 2018: 15-1252 (Software Developers)             → Level3 = $100K (median)
#
#   This ensures no duplicates while preserving specific wages where possible.
#
oflc_msa <- oflc_alc_all_years %>%
  filter(!is.na(Level3)) %>%
  select(SocCode, Area, PW_year, Level3, ACS_OCCSOC) %>%
  rename(MSA_code = Area) %>%
  mutate(
    MSA_code = as.character(MSA_code),
    # Clean SOC code (strip hyphens)
    SOC_CODE_clean = gsub("-", "", SocCode),
    SOC_CODE_clean = gsub("YY$", "XX", SOC_CODE_clean)
  ) %>%
  # Convert 2010 SOC codes to 2018 format for FY2021/2022
  left_join(
    soc_18_to_10 %>% rename(SOC_2010_clean = SOC_2010_clean, SOC_2018_clean = SOC_2018_clean),
    by = c("SOC_CODE_clean" = "SOC_2010_clean")
  ) %>%
  mutate(
    # For FY2021/2022: use converted 2018 code if available
    # For FY2023+: keep original code (already in 2018 format)
    SOC_CODE_clean = ifelse(
      PW_year %in% c(2021, 2022) & !is.na(SOC_2018_clean),
      SOC_2018_clean,
      SOC_CODE_clean
    )
  ) %>%
  select(-SOC_2018_clean) %>%
  # Aggregate when multiple 2010 codes map to one 2018 code
  group_by(SOC_CODE_clean, MSA_code, PW_year) %>%
  summarise(
    Level3 = median(Level3, na.rm = TRUE),
    ACS_OCCSOC = first(ACS_OCCSOC),
    .groups = "drop"
  )

cat("DIAGNOSTIC: After OFLC processing:\n")
cat("  Total rows:", nrow(oflc_msa), "\n")
cat("  Unique (SOC_CODE, MSA, Year) combos:",
    n_distinct(oflc_msa$SOC_CODE_clean, oflc_msa$MSA_code, oflc_msa$PW_year), "\n")
cat("  Sample rows:\n")
print(head(oflc_msa %>% select(SOC_CODE_clean, ACS_OCCSOC, MSA_code, PW_year, Level3), 10))
cat("\n")

# Join MSA-level first, fill gaps with national
# NOTE: Join by ACS_OCCSOC (not SocCode) to handle both SOC 2018 and SOC 2010 vintages

cat("DIAGNOSTIC: Before OFLC join:\n")
cat("  unique_combos rows:", nrow(unique_combos), "\n")
cat("  Sample unique_combos:\n")
print(head(unique_combos[, c("ACS_OCCSOC", "MSA_code", "PW_year")], 10))
cat("\n")

unique_combos <- unique_combos %>%
  left_join(oflc_msa %>% select(SOC_CODE_clean, MSA_code, PW_year, Level3),
            by = c("SOC_CODE_clean", "MSA_code", "PW_year"),
            relationship = "many-to-many") %>%
  rename(Level3_used = Level3)

cat("DIAGNOSTIC: After OFLC join:\n")
cat("  Combos with Level3_used:", sum(!is.na(unique_combos$Level3_used)), "\n")
cat("  Combos with NA Level3_used:", sum(is.na(unique_combos$Level3_used)), "\n\n")

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

cat("DIAGNOSTIC: Before ratio join:\n")
cat("  unique_combos with Level3_used:", sum(!is.na(unique_combos$Level3_used)), "\n")
cat("  Sample unique_combos keys:\n")
print(head(unique_combos[!is.na(unique_combos$Level3_used), c("ACS_OCCSOC", "highest_ed", "Years_pot_experience_rounded")], 10))
cat("\n")

unique_combos <- unique_combos %>%
  left_join(
    occ_edu_exp_ratios %>%
      select(OCCSOC, highest_ed, Years_pot_experience,
             ratio_p50, ratio_p62, ratio_p75, ratio_p90, model_level),
    by = c("ACS_OCCSOC" = "OCCSOC",
           "highest_ed" = "highest_ed",
           "Years_pot_experience_rounded" = "Years_pot_experience")
  )

cat("DIAGNOSTIC: After ratio join:\n")
cat("  Combos with ratio_p50:", sum(!is.na(unique_combos$ratio_p50)), "\n")
cat("  Combos with Level3_used AND ratio_p50:", sum(!is.na(unique_combos$Level3_used) & !is.na(unique_combos$ratio_p50)), "\n\n")

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
  select(SOC_CODE_clean, ACS_OCCSOC, MSA_code, highest_ed, Years_pot_experience, PW_year,
         pw_p50, pw_p62, pw_p75, pw_p90, pw_oflc_median, pw_model_used) %>%
  # Ensure no duplicate keys (should not be necessary, but adding as safeguard)
  distinct(SOC_CODE_clean, ACS_OCCSOC, MSA_code, highest_ed, Years_pot_experience, PW_year, .keep_all = TRUE)

cat("Wage prediction complete.\n")
cat("Combinations with valid wages:", sum(!is.na(unique_combos$pw_p50)), "\n")
cat("Combinations with NA wages:   ", sum(is.na(unique_combos$pw_p50)), "\n\n")

# =============================================================================
# STEP 3: JOIN WAGE RESULTS BACK TO FULL PETITION DATASET
# =============================================================================

h1b_22_24 <- h1b_22_24 %>%
  mutate(
    MSA_code = as.character(MSA_code),
    SOC_CODE_clean = as.character(gsub("-", "", SOC_CODE)),
    SOC_CODE_clean = gsub("YY$", "XX", SOC_CODE_clean)
  ) %>%
  # Join to unique_combos (OFLC data already converted to 2018 SOC format)
  left_join(
    unique_combos,
    by = c("SOC_CODE_clean", "ACS_OCCSOC", "MSA_code", "highest_ed",
           "Years_pot_experience", "PW_year"),
    relationship = "many-to-one"
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

