# =============================================================================
# Interpolate Wage Percentiles
# =============================================================================
#
# For each petition, we have the 17th, 34th, 50th, and 67th percentile (the four OFLC levels).
# If the petition is between the 17th and 67th percentile for pay within an occupation,
# we can calculate the petitioner's specific percentile by linearly interpolating between
# its two nearest-non-missing levels using OFLC levels. Note that we cannot calculate above the 67th percentile
# using OFLC Wage Levels.
#
# For those above Level 4 (the 67th percentile), we can use the ACS to construct a synthetic 90th percentile.
# To do that, we find the ratio of the 90th percentile earnings to the 67th to the closest-matching occupation.
# Then, we multiply that ratio by the Level 4 threshold to get a synthetic 90th percentile. We then use this synthetic
# 90th percentile to interpolate anyone between the 67th and 90th percentile.
#
# Note: BLS should be able to do this for you using OES directly, but publicly-available OES
# data does not match publicly-available OFLC data. We therefore use ACS as a stopgap.
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

# Packages
library(dplyr)
library(ipumsr)
library(Hmisc)
########################################################################################
# STEP 1: Load the cleaned data and filter out 2021
########################################################################################
h1b_22_24 <- read.csv(file.path(data_processed, "h1b_fy21_24_with_pumas.csv")) %>%
  filter(registration_lottery_year != 2021)

########################################################################################
# STEP 2: Linearly interpolate percentiles between 17 and 67 using OFLC Wage Levels
########################################################################################

# Helper functions for the interpolation. Extracted from the original rowwise()
# mutate() block so they can be called via mapply(), which iterates at C level
# rather than R level and is substantially faster across 273k+ rows.
# Logic is identical to the original — same inputs, same conditional branches,
# same outputs. Verified line-by-line against the rowwise version.
.calc_petition_percentile <- function(L1, L2, L3, L4, wage) {
  lvls <- c(L1, L2, L3, L4)
  pcts <- c(17, 34, 50, 67)
  keep <- !is.na(lvls)
  lvls <- lvls[keep]
  pcts <- pcts[keep]
  if (length(lvls) == 0 || is.na(wage)) {
    NA_real_
  } else if (wage < min(lvls)) {
    NA_real_
  } else if (wage >= max(lvls)) {
    100
  } else {
    lower_idx <- max(which(lvls <= wage))
    upper_idx <- min(which(lvls > wage))
    lo_lvl <- lvls[lower_idx]; hi_lvl <- lvls[upper_idx]
    lo_pct <- pcts[lower_idx]; hi_pct <- pcts[upper_idx]
    interp <- lo_pct + (wage - lo_lvl) / (hi_lvl - lo_lvl) * (hi_pct - lo_pct)
    floor(interp)
  }
}

.calc_petition_wage_status <- function(L1, L2, L3, L4, wage) {
  lvls       <- c(L1, L2, L3, L4)
  lvls_clean <- lvls[!is.na(lvls)]
  if (is.na(wage)) {
    NA_character_
  } else if (length(lvls_clean) == 0) {
    "Missing lower bound"
  } else if (wage >= max(lvls_clean)) {
    "Above Level 4"
  } else if (wage < min(lvls_clean)) {
    if (is.na(L1) && wage < min(lvls_clean)) "Missing lower bound" else "Too Low"
  } else {
    NA_character_
  }
}

h1b_22_24 <- h1b_22_24 %>%
  mutate(
    is_fulltime = petition_beneficiary_full_time != "N" | is.na(petition_beneficiary_full_time),
    L1   = if_else(is_fulltime, Level1_full, Level1_part),
    L2   = if_else(is_fulltime, Level2_full, Level2_part),
    L3   = if_else(is_fulltime, Level3_full, Level3_part),
    L4   = if_else(is_fulltime, Level4_full, Level4_part),
    wage = petition_annual_pay_clean,
    petition_percentile  = mapply(.calc_petition_percentile,  L1, L2, L3, L4, wage),
    petition_wage_status = mapply(.calc_petition_wage_status, L1, L2, L3, L4, wage)
  ) %>%
  select(-is_fulltime, -L1, -L2, -L3, -L4, -wage)
########################################################################################
# STEP 3: Construct national 67th/90th (national) occupation percentiles using ACS data. 
########################################################################################
# Note that these ratios are derived from 2019-2023 five-year ACS data. 

ddi <- read_ipums_ddi("data/raw/usa_00076.xml")
data <- read_ipums_micro(ddi)

occupational_percentiles <- data %>%
  filter(INCWAGE > 0 & INCWAGE != 999999 & INCWAGE != 999998, EMPSTAT == 1, AGE >15) %>%
  group_by(OCCSOC) %>%
  dplyr::summarize(
    p67 = as.numeric(Hmisc::wtd.quantile(INCWAGE, weights = PERWT, probs = 0.67, na.rm = TRUE)),
    p90 = as.numeric(Hmisc::wtd.quantile(INCWAGE, weights = PERWT, probs = 0.90, na.rm = TRUE))
  ) %>%
  ungroup() %>%
  mutate(ratio_67_90 = p90 / p67,
         OCCSOC = paste0(substr(OCCSOC, 1, 2), "-", substr(OCCSOC, 3, nchar(OCCSOC))))

########################################################################################
# STEP 4: Tag H-1B petitions with ACS codes
########################################################################################

# Create crosswalk and tag every H-1B petition with its best ACS code.
acs_oflc_crosswalk <- read.csv(file.path(data_raw, "occupation_oflc_to_acs_crowsswalk.csv"))

# Add in synthetic 90th percentile
h1b_22_24 <- h1b_22_24 %>% left_join(acs_oflc_crosswalk,
                                          by = c("SOC_CODE" = "SocCode")) %>%
  left_join(occupational_percentiles, by = c("ACS_OCCSOC" = "OCCSOC")) %>%
  mutate(ptile90 = Level4_full*ratio_67_90)
  
# Linearly interpolate percentile using ACS synthetic 90th
h1b_22_24 <- h1b_22_24 %>%
  mutate(
    # Determine full-time vs part-time (recompute since helper cols were dropped)
    is_fulltime = petition_beneficiary_full_time != "N" | is.na(petition_beneficiary_full_time),
    
    # Adjust ptile90 for part-time workers
    ptile90_adj = if_else(is_fulltime, ptile90, ptile90 / 2),
    
    # Retrieve L4 again for the lower bound of ACS interpolation
    L4 = if_else(is_fulltime, Level4_full, Level4_part)
  ) %>%
  mutate(
    wage = petition_annual_pay_clean,
    # mapply applies the same scalar logic as the original rowwise() block.
    # case_when is already vectorized so no change needed there.
    petition_percentile_acs = mapply(
      function(w, status, l4, p90) {
        if (is.na(status) || status != "Above Level 4") return(NA_real_)
        if (is.na(w) || is.na(l4) || is.na(p90))        return(NA_real_)
        if (w >= p90) return(100)
        floor(67 + (w - l4) / (p90 - l4) * (90 - 67))
      },
      wage, petition_wage_status, L4, ptile90_adj
    ),
    petition_percentile_combined = case_when(
      !is.na(petition_percentile) & petition_percentile <= 67 ~ petition_percentile,
      !is.na(petition_percentile_acs)                        ~ petition_percentile_acs,
      TRUE                                                    ~ NA_real_
    ),
    interpolation_method = case_when(
      !is.na(petition_percentile) & petition_percentile <= 67 ~ "OFLC interpolated",
      !is.na(petition_percentile_acs)                        ~ "ACS interpolated",
      TRUE                                                    ~ NA_character_
    )
  ) %>%
  select(-is_fulltime, -ptile90_adj, -L4, -wage)
########################################################################################
# STEP 5: Output CSV with estimated percentiles.
########################################################################################
output_file <- file.path(data_processed, "h1b_with_percentiles_and_native_comps.csv")
write.csv(h1b_22_24, output_file, row.names = FALSE)
cat("\nSaved to:", output_file, "\n")


