
# =============================================================================
# Mincer-Based Prevailing Wage Estimation
# =============================================================================
# PURPOSE:
#   Estimate a Mincer earnings equation using ACS microdata to produce a matrix
#   of prevailing wages for each combination of:
#     - Occupation (SOC code)
#     - Geographic area (from OFLC)
#     - Years of education
#     - Years of potential experience
#   at four wage levels: median (p50), 62nd percentile, 75th percentile, 90th.
#
# APPROACH:
#   Rather than materializing a full grid of ratios (which exceeds memory),
#   we store Mincer coefficients and occupation-level summary statistics,
#   then compute prevailing wages on the fly for any input combination.
#
# KEY DESIGN DECISION:
#   The OES-based OFLC Level 3 wage serves as the occupational median anchor
#   for each area-occupation. The Mincer equation estimates the SHAPE of the
#   education-experience curve within each occupation. These two pieces are
#   combined at query time rather than pre-computed as a full grid.
# =============================================================================

library(dplyr)
library(ipumsr)   # For reading IPUMS ACS extracts
library(fixest)   # For fast fixed effects estimation
library(Hmisc)    # For wtd.quantile()
library(purrr)    # For map() in per-occupation loop
library(readr)    # For write_csv / read_csv

setwd("~/Downloads")

# =============================================================================
# SECTION 1: LOAD AND CLEAN ACS DATA
# =============================================================================

# Load IPUMS ACS extract (5-year pooled 2019-2023)
ddi <- read_ipums_ddi("usa_00075.xml")
acs_data_19_23 <- read_ipums_micro(ddi)

# Clean and restrict to full-time, full-year workers with valid wages.
# This ensures the Mincer reflects the kind of workers prevailing wages apply to.
acs_data_19_23 <- acs_data_19_23 %>%
  filter(
    EMPSTAT ==1,
    INCWAGE != 999999,    # Remove top-coded wages
    INCWAGE != 999998,    # Remove missing wages
    INCWAGE > 0,          # Remove zero wages
    AGE > 15,             # Remove children
    !is.na(EDUCD)         # Remove missing education
  ) %>%
  mutate(
    # Convert IPUMS education codes to years of schooling.
    # These mappings follow standard Mincer literature conventions.
    Years_education = case_when(
      EDUCD < 14  ~ 0,   # No schooling / pre-1st grade
      EDUCD == 14 ~ 1,   # 1st grade
      EDUCD == 15 ~ 2,
      EDUCD == 16 ~ 3,
      EDUCD == 17 ~ 4,
      EDUCD == 22 ~ 5,
      EDUCD == 23 ~ 6,
      EDUCD == 25 ~ 7,
      EDUCD == 26 ~ 8,
      EDUCD == 30 ~ 9,
      EDUCD == 40 ~ 10,
      EDUCD == 50 ~ 11,
      EDUCD == 61 ~ 11,  # Some HS, no diploma
      EDUCD == 63 ~ 12,  # HS diploma
      EDUCD == 64 ~ 12,  # GED
      EDUCD == 65 ~ 12,  # <1 year of college — round down
      EDUCD == 71 ~ 13,  # 1+ year of college
      EDUCD == 81 ~ 14,  # Associate's degree
      EDUCD == 101 ~ 16, # Bachelor's degree — assume 4 years
      EDUCD == 114 ~ 18, # Master's degree — assume 2 years post-BA
      EDUCD == 115 ~ 19, # Professional degree — assume 3 years post-BA
      EDUCD == 116 ~ 23, # PhD — assume 5 years post-BA
      TRUE ~ NA
    ),
    
    # Mincer potential experience: age minus years of education minus 6
    # (6 = assumed age at start of schooling). Floored at 0.
    Years_pot_experience = pmax(AGE - Years_education - 6, 0),
    
    # Log wage is the dependent variable in the Mincer equation
    log_incwage = log(INCWAGE),
    highest_ed = case_when(EDUCD < 62 ~ "Less than HS",
                               EDUCD > 62 & EDUCD < 81~ "High school",
                               EDUCD == 81 ~ "Associates",
                               EDUCD == 101 ~ "Bachelors",
                               EDUCD == 114 ~ "Masters",
                               EDUCD == 115 ~ "Prof degree",
                               EDUCD == 116 ~ "PhD")
  )

# =============================================================================
# SECTION 2: ESTIMATE MINCER EQUATIONS BY OCCUPATION
# =============================================================================
# We estimate a SEPARATE Mincer equation for each occupation. This allows the
# returns to education and experience to vary across occupations — e.g., 
# experience may matter more in skilled trades than in professional services.
#
# Since the OES median already anchors the wage level for each occupation-area,
# we do NOT include an occupation fixed effect here. The occupation intercept
# would cancel out when we compute ratios in Section 3.
#
# For occupations with fewer than 100 ACS respondents (unweighted), we fall
# back to a pooled national Mincer to avoid overfitting on thin samples.
# =============================================================================

# --- 2a. Estimate pooled national Mincer as fallback ---
mincer_pooled <- feols(
  log_incwage ~
    Years_pot_experience +
    I(Years_pot_experience^2) +
    I(Years_pot_experience^3) +
    I(Years_pot_experience^4) +
    highest_ed | MET2013,
  data    = acs_data_19_23,
  weights = ~PERWT
)

pooled_coefs <- coef(mincer_pooled)

# --- 2b. Estimate per-occupation Mincers ---
occs <- unique(acs_data_19_23$OCCSOC)
occ_models <- vector("list", length(occs))

for (i in seq_along(occs)) {
  occ <- occs[i]
  occ_data <- acs_data_19_23 %>% filter(OCCSOC == occ)
  
  if (i %% 50 == 0) cat("Fitting model", i, "of", length(occs), "\n")
  
  raw_median <- wtd.quantile(occ_data$INCWAGE, weights = occ_data$PERWT, probs = 0.50)
  p62 <- wtd.quantile(occ_data$INCWAGE, weights = occ_data$PERWT, probs = 0.62)
  p75 <- wtd.quantile(occ_data$INCWAGE, weights = occ_data$PERWT, probs = 0.75)
  p90 <- wtd.quantile(occ_data$INCWAGE, weights = occ_data$PERWT, probs = 0.90)
  
  ratio_p62 <- p62 / raw_median
  ratio_p75 <- p75 / raw_median
  ratio_p90 <- p90 / raw_median
  
  use_pooled <- nrow(occ_data) < 100
  
  if (!use_pooled) {
    m <- tryCatch(
      feols(
        log_incwage ~
          Years_pot_experience +
          I(Years_pot_experience^2) +
          I(Years_pot_experience^3) +
          I(Years_pot_experience^4) +
          highest_ed | MET2013,
        data    = occ_data,
        weights = ~PERWT
      ),
      error = function(e) NULL
    )
    if (is.null(m)) use_pooled <- TRUE
  }
  
  coefs <- if (use_pooled) pooled_coefs else coef(m)
  
  occ_models[[i]] <- list(
    OCCSOC      = occ,
    coefs       = coefs,
    raw_median  = raw_median,
    ratio_p62   = ratio_p62,
    ratio_p75   = ratio_p75,
    ratio_p90   = ratio_p90,
    used_pooled = use_pooled
  )
  
  rm(occ_data, raw_median, p62, p75, p90)
  if (!use_pooled && exists("m")) rm(m)
}

n_pooled <- sum(sapply(occ_models, function(x) x$used_pooled))
cat(n_pooled, "of", length(occs), "occupations used the pooled fallback model\n")

# Extract coefficients — education categories replace continuous education terms.
# R names dummy coefficients as "highest_edCATEGORY" with the reference level omitted.
# The reference category here is "Associates" (first alphabetically) unless you 
# explicitly set factor levels in Section 1 — check names(pooled_coefs) to confirm.
occ_model_df <- bind_rows(lapply(occ_models, function(x) {
  data.frame(
    OCCSOC               = x$OCCSOC,
    raw_median           = x$raw_median,
    ratio_p62            = x$ratio_p62,
    ratio_p75            = x$ratio_p75,
    ratio_p90            = x$ratio_p90,
    used_pooled          = x$used_pooled,
    b_intercept          = x$coefs["(Intercept)"],
    b_exp1               = x$coefs["Years_pot_experience"],
    b_exp2               = x$coefs["I(I(Years_pot_experience^2))"],
    b_exp3               = x$coefs["I(I(Years_pot_experience^3))"],
    b_exp4               = x$coefs["I(I(Years_pot_experience^4))"],
    b_ed_Bachelors       = x$coefs["highest_edBachelors"],
    b_ed_HighSchool      = x$coefs["highest_edHigh school"],
    b_ed_LessThanHS      = x$coefs["highest_edLess than HS"],
    b_ed_Masters         = x$coefs["highest_edMasters"],
    b_ed_PhD             = x$coefs["highest_edPhD"],
    b_ed_ProfDegree      = x$coefs["highest_edProf degree"],
    stringsAsFactors = FALSE
  )
}))

write_csv(occ_model_df, "occ_model_coefficients.csv")

rm(acs_data_19_23, occ_models, mincer_pooled)
gc()

# =============================================================================
# SECTION 3: DEFINE WAGE PREDICTION FUNCTION
# =============================================================================
# Rather than pre-computing a full grid, we define a function that computes
# the prevailing wage for a given input on the fly using stored coefficients.
#
# For a given occupation, education category, experience, and OES median:
#   1. Predict log wage using stored Mincer coefficients
#   2. Compute ratio = exp(predicted log wage - log(ACS raw median))
#   3. Scale OES median by ratio to get p50 prevailing wage
#   4. Apply fixed percentile scalars to get p62, p75, p90
#
# Education is now a categorical variable. The coefficient for the reference
# category (whichever level was omitted in estimation) is implicitly zero —
# i.e. the intercept already captures the reference category's wage level.
# =============================================================================

predict_wage <- function(coef_row, highest_ed, years_exp, oflc_level3) {
  
  # Look up the education dummy coefficient for the specified category.
  # The reference category (omitted in estimation) gets a coefficient of 0.
  # Column names in coef_row follow the pattern b_ed_CATEGORY.
  ed_coef <- case_when(
    highest_ed == "Bachelors"    ~ coef_row$b_ed_Bachelors,
    highest_ed == "High school"  ~ coef_row$b_ed_HighSchool,
    highest_ed == "Less than HS" ~ coef_row$b_ed_LessThanHS,
    highest_ed == "Masters"      ~ coef_row$b_ed_Masters,
    highest_ed == "PhD"          ~ coef_row$b_ed_PhD,
    highest_ed == "Prof degree"  ~ coef_row$b_ed_ProfDegree,
    TRUE ~ 0  # Reference category (Associates) has implicit coefficient of 0
  )
  
  # Evaluate the Mincer at the given education category and experience values.
  # The intercept cancels out in the ratio and could be excluded, but is
  # retained here for clarity — it drops out when we subtract log(raw_median).
  log_wage_hat <- coef_row$b_intercept +
    coef_row$b_exp1 * years_exp +
    coef_row$b_exp2 * years_exp^2 +
    coef_row$b_exp3 * years_exp^3 +
    coef_row$b_exp4 * years_exp^4 +
    ed_coef
  
  # Ratio of predicted wage at this (education, experience) cell to the
  # occupation's ACS median. Captures how much more/less this worker profile
  # earns relative to the typical worker in this occupation nationally.
  ratio_p50 <- exp(log_wage_hat - log(coef_row$raw_median))
  
  # Scale the OES median (OFLC Level 3) by the ratio to get the p50 wage.
  # Apply fixed percentile scalars for higher wage levels.
  # Monotonicity is guaranteed since ratio_p62/p75/p90 are fixed positive
  # constants derived from the empirical ACS distribution.
  data.frame(
    wage_p50 = oflc_level3 * ratio_p50,
    wage_p62 = oflc_level3 * ratio_p50 * coef_row$ratio_p62,
    wage_p75 = oflc_level3 * ratio_p50 * coef_row$ratio_p75,
    wage_p90 = oflc_level3 * ratio_p50 * coef_row$ratio_p90
  )
}
# =============================================================================
# SECTION 4: LOAD OFLC DATA AND CROSSWALK
# =============================================================================

acs_oflc_crosswalk <- read.csv("occupation_oflc_to_acs_crowsswalk.csv")

# --- 4a. ALC (standard prevailing wages) ---
oflc_levels_alc <- read.csv("OFLC_Wages_2025-26_Updated 2/ALC_Export.csv") %>%
  mutate(Level3 = ifelse(Level3 > 350, Level3, Level3 * 2080),
         Level3 = ifelse(Label == "High Wage", 239200, Level3)) %>%
  select(Area, SocCode, GeoLvl, Level3)

oflc_base_alc <- left_join(oflc_levels_alc, acs_oflc_crosswalk, by = "SocCode") %>%
  mutate(ACS_OCCSOC = gsub("-", "", ACS_OCCSOC)) %>%
  select(Area, SocCode, GeoLvl, Level3, ACS_OCCSOC)

# --- 4b. EDC (ACWIA prevailing wages) ---
oflc_levels_edc <- read.csv("OFLC_Wages_2025-26_Updated 2/EDC_Export.csv") %>%
  mutate(Level3 = ifelse(Level3 > 350, Level3, Level3 * 2080),
         Level3 = ifelse(Label == "High Wage", 239200, Level3)) %>%
  select(Area, SocCode, GeoLvl, Level3)

oflc_base_edc <- left_join(oflc_levels_edc, acs_oflc_crosswalk, by = "SocCode") %>%
  mutate(ACS_OCCSOC = gsub("-", "", ACS_OCCSOC)) %>%
  select(Area, SocCode, GeoLvl, Level3, ACS_OCCSOC)

# =============================================================================
# SECTION 5: COMPUTE PREVAILING WAGES
# =============================================================================

edu_grid <- c("Less than HS", "High school", "Associates",
              "Bachelors", "Masters", "Prof degree", "PhD")
exp_grid <- seq(0, 45, by = 1)

# Helper function to run the output loop for a given oflc_base and output file
# This avoids duplicating the loop code for ALC and EDC
run_prevailing_wage_loop <- function(oflc_base, output_file) {
  
  if (file.exists(output_file)) file.remove(output_file)
  
  occs_to_process <- unique(oflc_base$ACS_OCCSOC[
    oflc_base$ACS_OCCSOC %in% unique(occ_model_df$OCCSOC)
  ])
  
  cat("Processing", length(occs_to_process), "occupations for", output_file, "\n")
  
  for (i in seq_along(occs_to_process)) {
    occ <- occs_to_process[i]
    
    if (i %% 50 == 0) cat("Processing occupation", i, "of", length(occs_to_process), "\n")
    
    oflc_occ <- oflc_base %>% filter(ACS_OCCSOC == occ)
    coef_row  <- occ_model_df %>% filter(OCCSOC == occ)
    
    if (nrow(coef_row) == 0 || nrow(oflc_occ) == 0) next
    
    edu_exp_grid <- expand.grid(
      highest_ed           = edu_grid,
      Years_pot_experience = exp_grid,
      stringsAsFactors     = FALSE
    )
    
    wage_preds <- predict_wage(
      coef_row    = coef_row,
      highest_ed  = edu_exp_grid$highest_ed,
      years_exp   = edu_exp_grid$Years_pot_experience,
      oflc_level3 = 1
    )
    
    edu_exp_grid <- cbind(edu_exp_grid, wage_preds)
    
    chunk <- oflc_occ %>%
      cross_join(edu_exp_grid) %>%
      mutate(
        wage_p50 = Level3 * wage_p50,
        wage_p62 = Level3 * wage_p62,
        wage_p75 = Level3 * wage_p75,
        wage_p90 = Level3 * wage_p90
      ) %>%
      select(Area, SocCode, highest_ed, Years_pot_experience,
             wage_p50, wage_p62, wage_p75, wage_p90)
    
    write_csv(chunk, output_file, append = (i > 1))
    
    rm(oflc_occ, edu_exp_grid, wage_preds, chunk)
    gc()
  }
  
  cat("Done. Output written to", output_file, "\n")
}

# Run for both datasets
run_prevailing_wage_loop(oflc_base_alc, "prevailing_wages_alc.csv")
run_prevailing_wage_loop(oflc_base_edc, "prevailing_wages_edc.csv")

cat("Done. Output written to", output_file, "\n")

# =============================================================================
# SECTION 6: VALIDATION
# =============================================================================

# Read final output and run basic sanity checks
# prevailing_wages <- read_csv(output_file)
# 
# # Check monotonicity: wage levels should always increase p50 -> p62 -> p75 -> p90
# monotonicity_check <- prevailing_wages %>%
#   summarise(
#     any_p62_below_p50 = any(wage_p62 < wage_p50, na.rm = TRUE),
#     any_p75_below_p62 = any(wage_p75 < wage_p62, na.rm = TRUE),
#     any_p90_below_p75 = any(wage_p90 < wage_p75, na.rm = TRUE)
#   )
# print(monotonicity_check)
# # All should be FALSE — monotonicity is guaranteed by construction since
# # the percentile scalars are fixed positive constants > 1.
# 
# # Check coverage: how many area-occupation combinations have wage estimates?
# cat("Total rows:", nrow(prevailing_wages), "\n")
# cat("Unique area-occupation combinations:",
#     n_distinct(prevailing_wages %>% select(Area, SocCode)), "\n")
# cat("Education-experience cells per combo:",
#     length(edu_grid) * length(exp_grid), "\n")

# =============================================================================
# SECTION 7: SPOT CHECK — LOOK UP A SPECIFIC WORKER PROFILE
# =============================================================================
# Given a specific occupation, area, education category, and years of
# potential experience, return the four prevailing wage levels.
#
# wage_type controls which prevailing wage schedule is used:
#   "ALC" = standard prevailing wages (used for most H-1B and PERM cases)
#   "EDC" = ACWIA prevailing wages (used for H-1B dependent employers)
#
# Usage examples at the bottom of this section.
# =============================================================================

# Load from disk if not already in memory
# oflc_base_alc <- ... (built in Section 4)
# oflc_base_edc <- ... (built in Section 4)
# occ_model_df  <- read_csv("occ_model_coefficients.csv")

lookup_prevailing_wage <- function(soc_code, area, highest_ed, years_exp,
                                   wage_type = "ALC") {
  
  # Validate wage_type argument
  if (!wage_type %in% c("ALC", "EDC")) {
    stop("wage_type must be 'ALC' (standard prevailing wages) or 'EDC' (ACWIA prevailing wages)")
  }
  
  # Select the appropriate OFLC base table based on wage type
  oflc_base <- if (wage_type == "ALC") oflc_base_alc else oflc_base_edc
  
  # Validate education category
  valid_ed <- c("Less than HS", "High school", "Associates",
                "Bachelors", "Masters", "Prof degree", "PhD")
  if (!highest_ed %in% valid_ed) {
    stop("highest_ed must be one of: ", paste(valid_ed, collapse = ", "))
  }
  
  # Pull the OFLC Level 3 median for this occupation-area combination
  oflc_row <- oflc_base %>%
    filter(SocCode == soc_code, Area == area)
  
  # If no MSA-level match, fall back to national (GeoLvl == "N")
  if (nrow(oflc_row) == 0 || is.na(oflc_row$Level3[1])) {
    cat("No MSA-level wage found for", soc_code, "in area", area,
        "— falling back to national wage\n")
    oflc_row <- oflc_base %>%
      filter(SocCode == soc_code, GeoLvl == "N")
  }
  
  if (nrow(oflc_row) == 0 || is.na(oflc_row$Level3[1])) {
    stop("No OFLC wage found for SocCode ", soc_code, 
         " at any geography level in ", wage_type, " data")
  }
  
  # Pull the stored Mincer coefficients for the mapped ACS occupation
  coef_row <- occ_model_df %>%
    filter(OCCSOC == oflc_row$ACS_OCCSOC[1])
  
  if (nrow(coef_row) == 0) {
    stop("No Mincer model found for ACS occupation ", oflc_row$ACS_OCCSOC[1])
  }
  
  # Compute wages using stored coefficients
  wages <- predict_wage(
    coef_row    = coef_row,
    highest_ed  = highest_ed,
    years_exp   = years_exp,
    oflc_level3 = oflc_row$Level3[1]
  )
  
  # Return a readable summary
  data.frame(
    wage_type   = wage_type,             # ALC or EDC
    Area        = oflc_row$Area[1],      # Area actually used (may differ if fallback triggered)
    GeoLvl      = oflc_row$GeoLvl[1],   # Geography level used (1=MSA, N=national)
    SocCode     = soc_code,
    ACS_OCCSOC  = oflc_row$ACS_OCCSOC[1],
    highest_ed  = highest_ed,
    Years_exp   = years_exp,
    OES_median  = oflc_row$Level3[1],
    wage_p50    = round(wages$wage_p50),
    wage_p62    = round(wages$wage_p62),
    wage_p75    = round(wages$wage_p75),
    wage_p90    = round(wages$wage_p90),
    used_pooled = coef_row$used_pooled
  )
}

# -----------------------------------------------------------------------------
# USAGE EXAMPLES
# -----------------------------------------------------------------------------

# Look up ALC (standard) prevailing wage only
lookup_prevailing_wage(
  soc_code   = "25-1065",
  area       = "41860",   # San Francisco
  highest_ed = "Masters",
  years_exp  = 5,
  wage_type  = "ALC"
)

# Look up EDC (ACWIA) prevailing wage only
lookup_prevailing_wage(
  soc_code   = "25-1065",
  area       = "41860",
  highest_ed = "Masters",
  years_exp  = 5,
  wage_type  = "EDC"
)

# Compare ALC and EDC side by side for the same worker profile
rbind(
  lookup_prevailing_wage("15-1252", "41860", "Masters", 5, wage_type = "ALC"),
  lookup_prevailing_wage("15-1252", "41860", "Masters", 5, wage_type = "EDC")
)