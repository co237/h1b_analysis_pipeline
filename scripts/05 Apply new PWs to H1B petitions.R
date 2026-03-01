# =============================================================================
# Tag H-1B Petitions with Mincer-Based Prevailing Wages
# =============================================================================
#
# PREREQUISITES:
#   mincer_prevailing_wages.R must have been run in the same session so that
#   the following objects are available in memory:
#     - occ_area_models  — list of fitted Mincer models by occupation and area
#     - oflc_bases       — nested list of OFLC wage tables by type and year
#     - predict_wage()   — wage prediction function
#
# INPUT:
#   h1b_with_percentiles_and_native_comps.csv — cleaned H-1B petition file
#
# OUTPUT:
#   h1b_with_mincer_wages.csv — same file with four prevailing wage columns added
#
# =============================================================================

# Confirm prerequisites are available
if (!exists("occ_area_models") || !exists("oflc_bases") || !exists("predict_wage")) {
  stop("Please run mincer_prevailing_wages.R first to populate ",
       "occ_area_models, oflc_bases, and predict_wage() in your session.")
}

# =============================================================================
# STEP 0: LOAD AND PREPARE H-1B DATA
# =============================================================================

h1b_22_24 <- read.csv("h1b_with_percentiles_and_native_comps.csv")

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
    
    # SOC_CODE already has the hyphen (e.g. "15-1252") — use directly
    SocCode_hyphen = SOC_CODE,
    
    # Stripped and truncated codes (kept for reference, not used in lookup)
    SocCode = gsub("-", "", SOC_CODE),
    SOC5    = substr(SocCode, 1, 5),
    SOC3    = substr(SocCode, 1, 3),
    SOC2    = substr(SocCode, 1, 2)
  )

# =============================================================================
# STEP 1: IDENTIFY UNIQUE LOOKUP COMBINATIONS
# =============================================================================
#
# Rows missing any of SOC code, MSA code, education, experience, or year
# cannot be looked up and will receive NA wages via the left join in Step 3.
#
# =============================================================================

unique_combos <- h1b_22_24 %>%
  filter(
    !is.na(SocCode_hyphen),
    !is.na(MSA_code),
    !is.na(highest_ed),
    !is.na(Years_pot_experience),
    !is.na(PW_year)
  ) %>%
  mutate(MSA_code = as.character(MSA_code)) %>%
  distinct(SocCode_hyphen, MSA_code, highest_ed, Years_pot_experience, PW_year)

cat("Total H-1B petitions:", nrow(h1b_22_24), "\n")
cat("Unique lookup combinations:", nrow(unique_combos), "\n")
cat("Petitions missing required fields (will receive NA wages):",
    nrow(h1b_22_24) - sum(
      !is.na(h1b_22_24$SocCode_hyphen) &
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
oflc_msa <- oflc_alc_all_years %>%
  filter(!is.na(Level3)) %>%
  select(SocCode, Area, PW_year, Level3, ACS_OCCSOC) %>%
  rename(MSA_code = Area) %>%
  mutate(MSA_code = as.character(MSA_code))

# National fallback wages
oflc_national_oes <- oflc_alc_all_years %>%
  filter(GeoLvl == "N", !is.na(Level3)) %>%
  select(SocCode, PW_year, Level3, ACS_OCCSOC) %>%
  rename(Level3_national    = Level3,
         ACS_OCCSOC_national = ACS_OCCSOC)

# Join MSA-level first, fill gaps with national
unique_combos <- unique_combos %>%
  left_join(oflc_msa,
            by = c("SocCode_hyphen" = "SocCode", "MSA_code", "PW_year")) %>%
  left_join(oflc_national_oes,
            by = c("SocCode_hyphen" = "SocCode", "PW_year")) %>%
  mutate(
    Level3_used   = ifelse(!is.na(Level3), Level3, Level3_national),
    ACS_OCCSOC    = ifelse(!is.na(ACS_OCCSOC), ACS_OCCSOC, ACS_OCCSOC_national),
    oflc_geo_used = ifelse(!is.na(Level3), as.character(MSA_code), "National fallback")
  ) %>%
  select(-Level3, -Level3_national, -ACS_OCCSOC_national)

# --- 2b. Extract Mincer coefficients into a flat data frame and join ---

coef_df <- bind_rows(lapply(occ_area_models, function(m) {
  data.frame(
    ACS_OCCSOC    = m$OCCSOC,
    model_area    = as.character(m$Area),  # "NATIONAL" or a metro code string
    raw_median    = m$raw_median,
    ratio_p62     = m$ratio_p62,
    ratio_p75     = m$ratio_p75,
    ratio_p90     = m$ratio_p90,
    model_level   = m$model_level,
    b_intercept   = m$coefs["(Intercept)"],
    b_exp1        = m$coefs["Years_pot_experience"],
    b_exp2        = m$coefs["I(I(Years_pot_experience^2))"],
    b_exp3        = m$coefs["I(I(Years_pot_experience^3))"],
    b_exp4        = m$coefs["I(I(Years_pot_experience^4))"],
    b_LessThanHS  = m$coefs["highest_edLess than HS"],
    b_HighSchool  = m$coefs["highest_edHigh school"],
    b_SomeCollege = m$coefs["highest_edSome college"],
    b_Bachelors   = m$coefs["highest_edBachelors"],
    b_Masters     = m$coefs["highest_edMasters"],
    b_ProfDegree  = m$coefs["highest_edProf degree"],
    b_PhD         = m$coefs["highest_edPhD"],
    stringsAsFactors = FALSE
  )
}))

# Area-specific models — keep model_area for joining, drop after
coef_area <- coef_df %>%
  filter(model_area != "NATIONAL")
# NOTE: do NOT select(-model_area) here — it is needed as the join key below

# National fallback models — rename all coefficient columns with _nat suffix
coef_national_mincer <- coef_df %>%
  filter(model_area == "NATIONAL") %>%
  select(-model_area) %>%
  rename_with(~ paste0(.x, "_nat"), -ACS_OCCSOC)

# Join area-specific first (matched on both ACS_OCCSOC and MSA_code),
# then national fallback (matched on ACS_OCCSOC only).
# Where area-specific coefficients exist they take priority; otherwise
# the ifelse() calls below fill in from the _nat columns.
unique_combos <- unique_combos %>%
  left_join(coef_area,
            by = c("ACS_OCCSOC", "MSA_code" = "model_area")) %>%
  left_join(coef_national_mincer, by = "ACS_OCCSOC") %>%
  mutate(
    raw_median    = ifelse(!is.na(raw_median),    raw_median,    raw_median_nat),
    ratio_p62     = ifelse(!is.na(ratio_p62),     ratio_p62,     ratio_p62_nat),
    ratio_p75     = ifelse(!is.na(ratio_p75),     ratio_p75,     ratio_p75_nat),
    ratio_p90     = ifelse(!is.na(ratio_p90),     ratio_p90,     ratio_p90_nat),
    model_level   = ifelse(!is.na(model_level),   model_level,
                           paste0("occupation-wide: ", model_level_nat)),
    b_intercept   = ifelse(!is.na(b_intercept),   b_intercept,   b_intercept_nat),
    b_exp1        = ifelse(!is.na(b_exp1),         b_exp1,        b_exp1_nat),
    b_exp2        = ifelse(!is.na(b_exp2),         b_exp2,        b_exp2_nat),
    b_exp3        = ifelse(!is.na(b_exp3),         b_exp3,        b_exp3_nat),
    b_exp4        = ifelse(!is.na(b_exp4),         b_exp4,        b_exp4_nat),
    b_LessThanHS  = ifelse(!is.na(b_LessThanHS),   b_LessThanHS,  b_LessThanHS_nat),
    b_HighSchool  = ifelse(!is.na(b_HighSchool),   b_HighSchool,  b_HighSchool_nat),
    b_SomeCollege = ifelse(!is.na(b_SomeCollege),  b_SomeCollege, b_SomeCollege_nat),
    b_Bachelors   = ifelse(!is.na(b_Bachelors),    b_Bachelors,   b_Bachelors_nat),
    b_Masters     = ifelse(!is.na(b_Masters),      b_Masters,     b_Masters_nat),
    b_ProfDegree  = ifelse(!is.na(b_ProfDegree),   b_ProfDegree,  b_ProfDegree_nat),
    b_PhD         = ifelse(!is.na(b_PhD),          b_PhD,         b_PhD_nat)
  ) %>%
  select(-ends_with("_nat"))

# --- 2c. Vectorized Mincer prediction ---
# All arithmetic runs on full columns — no loop, no rowwise().

unique_combos <- unique_combos %>%
  mutate(
    ed_coef = case_when(
      highest_ed == "Less than HS" ~ b_LessThanHS,
      highest_ed == "High school"  ~ b_HighSchool,
      highest_ed == "Some college" ~ b_SomeCollege,
      highest_ed == "Bachelors"    ~ b_Bachelors,
      highest_ed == "Masters"      ~ b_Masters,
      highest_ed == "Prof degree"  ~ b_ProfDegree,
      highest_ed == "PhD"          ~ b_PhD,
      TRUE ~ 0   # Associates: reference category, coefficient = 0
    ),
    
    log_wage_hat = b_intercept +
      b_exp1 * Years_pot_experience +
      b_exp2 * Years_pot_experience^2 +
      b_exp3 * Years_pot_experience^3 +
      b_exp4 * Years_pot_experience^4 +
      ed_coef,
    
    ratio_p50      = exp(log_wage_hat - log(raw_median)),
    pw_p50         = round(Level3_used * ratio_p50),
    pw_p62         = round(Level3_used * ratio_p50 * ratio_p62),
    pw_p75         = round(Level3_used * ratio_p50 * ratio_p75),
    pw_p90         = round(Level3_used * ratio_p50 * ratio_p90),
    pw_oflc_median = Level3_used,
    pw_model_used  = model_level
  ) %>%
  select(SocCode_hyphen, MSA_code, highest_ed, Years_pot_experience, PW_year,
         pw_p50, pw_p62, pw_p75, pw_p90, pw_oflc_median, pw_model_used)

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
    by = c("SocCode_hyphen", "MSA_code", "highest_ed",
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

write.csv(h1b_22_24, "h1b_with_mincer_wages.csv", row.names = FALSE)
cat("Saved to h1b_with_mincer_wages.csv\n")


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

