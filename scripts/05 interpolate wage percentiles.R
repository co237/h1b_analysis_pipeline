# Calculate underpayment rates for NPRM cutoffs.

# For each petition, we have the 17th, 34th, 50th, and 67th percentile (the four OFLC levels). 
# If the petition is between the 17th and 67th percentile for pay within an occupation,
# we can calculate the petitioner's specific percentile by linearly interpolating between
# its two nearest-non-missing levels using OFLC levels. Note that we cannot calculate above the 67th percentile
# using OFLC Wage Levels. 

# For those above Level 4 (the 67th percentile), we can use the ACS to construct a synthetic 90th percentile.
# To do that, we find the ratio of the 90th percentile earnings to the 67th to the closest-matching occupation.
# Then, we multiply that ratio by the Level 4 threshold to get a synthetic 90th percentile. We then use this synthetic
# 90th percentile to interpolate anyone between the 67th and 90th percentile. 

# Note: BLS should be able to do this for you using OES directly, but publicly-available OES
# data does not match publicly-available OFLC data. We therefore use ACS as a stopgap. 

# Packages
library(dplyr)
library(ipumsr)
library(Hmisc)

# Step 1: Load the cleaned data and filter out 2021
h1b_22_24 <- read.csv("data/processed/h1b_fy21_24_with_pumas.csv") %>%
  filter(registration_lottery_year != 2021)

# Step 2: Linearly interpolate percentiles between 17 and 67 using OFLC Wage Levels
h1b_22_24 <- h1b_22_24 %>%
  mutate(
    # Determine full-time vs part-time
    is_fulltime = petition_beneficiary_full_time != "N" | is.na(petition_beneficiary_full_time),
    
    # Select the correct wage level thresholds for each petition
    L1 = if_else(is_fulltime, Level1_full, Level1_part),
    L2 = if_else(is_fulltime, Level2_full, Level2_part),
    L3 = if_else(is_fulltime, Level3_full, Level3_part),
    L4 = if_else(is_fulltime, Level4_full, Level4_part),
    
    # Anchor percentiles
    P1 = 17, P2 = 34, P3 = 50, P4 = 67
  ) %>%
  rowwise() %>%
  mutate(
    wage = petition_annual_pay_clean,
    
    # Build a named lookup of non-missing (level, percentile) pairs
    # then interpolate based on where wage falls
    
    petition_percentile = {
      # Collect non-missing thresholds as a small lookup
      lvls <- c(L1, L2, L3, L4)
      pcts <- c(17, 34, 50, 67)
      keep <- !is.na(lvls)
      lvls <- lvls[keep]
      pcts <- pcts[keep]
      
      if (length(lvls) == 0 || is.na(wage)) {
        NA_real_
      } else if (wage < min(lvls)) {
        NA_real_  # Too Low or Missing lower bound — handled in status variable
      } else if (wage >= max(lvls)) {
        100
      } else {
        # Find the two closest non-missing levels that bracket the wage
        lower_idx <- max(which(lvls <= wage))
        upper_idx <- min(which(lvls > wage))
        lo_lvl <- lvls[lower_idx]; hi_lvl <- lvls[upper_idx]
        lo_pct <- pcts[lower_idx]; hi_pct <- pcts[upper_idx]
        # Linear interpolation
        interp <- lo_pct + (wage - lo_lvl) / (hi_lvl - lo_lvl) * (hi_pct - lo_pct)
        floor(interp)
      }
    },
    
    petition_wage_status = {
      lvls <- c(L1, L2, L3, L4)
      pcts <- c(17, 34, 50, 67)
      keep <- !is.na(lvls)
      lvls_clean <- lvls[keep]
      
      if (is.na(wage)) {
        NA_character_
      } else if (length(lvls_clean) == 0) {
        "Missing lower bound"
      } else if (wage >= max(lvls_clean)) {
        "Above Level 4"
      } else if (wage < min(lvls_clean)) {
        # Check: is Level 1 missing and the wage is below the lowest available level?
        if (is.na(L1) && wage < min(lvls_clean)) {
          "Missing lower bound"
        } else {
          "Too Low"
        }
      } else {
        NA_character_
      }
    }
    
  ) %>%
  ungroup() %>%
  # Clean up helper columns
  select(-is_fulltime, -L1, -L2, -L3, -L4, -P1, -P2, -P3, -P4, -wage)

# Step 3: Construct national 67th/90th (national) occupation percentiles using ACS data. 
# Note that these ratios are derived from 2019-2023 five-year ACS data. 

ddi <- read_ipums_ddi("data/raw/usa_00074.xml")
data <- read_ipums_micro(ddi)

occupational_percentiles <- data %>%
  filter(INCWAGE > 0 & INCWAGE != 999999 & INCWAGE != 999998) %>%
  group_by(OCCSOC) %>%
  dplyr::summarize(
    p67 = as.numeric(Hmisc::wtd.quantile(INCWAGE, weights = PERWT, probs = 0.67, na.rm = TRUE)),
    p90 = as.numeric(Hmisc::wtd.quantile(INCWAGE, weights = PERWT, probs = 0.90, na.rm = TRUE))
  ) %>%
  ungroup() %>%
  mutate(ratio_67_90 = p90 / p67,
         OCCSOC = paste0(substr(OCCSOC, 1, 2), "-", substr(OCCSOC, 3, nchar(OCCSOC))))

# Step 4: Tag H-1B petitions with ACS codes

# Create crosswalk and tag every H-1B petition with its best ACS code.
acs_oflc_crosswalk <- read.csv("data/raw/occupation_oflc_to_acs_crowsswalk.csv")

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
  rowwise() %>%
  mutate(
    wage = petition_annual_pay_clean,
    
    # --- ACS interpolation (67th–90th percentile) ---
    # Only attempt for "Above Level 4" petitions
    petition_percentile_acs = {
      if (is.na(petition_wage_status) || petition_wage_status != "Above Level 4") {
        NA_real_
      } else if (is.na(wage) || is.na(L4) || is.na(ptile90_adj)) {
        NA_real_
      } else if (wage >= ptile90_adj) {
        100
      } else {
        # Interpolate between L4 (67th pct) and ptile90_adj (90th pct)
        interp <- 67 + (wage - L4) / (ptile90_adj - L4) * (90 - 67)
        floor(interp)
      }
    },
    
    # --- Combined percentile column ---
    petition_percentile_combined = case_when(
      !is.na(petition_percentile) & petition_percentile <= 67 ~ petition_percentile,
      !is.na(petition_percentile_acs)                        ~ petition_percentile_acs,
      TRUE                                                    ~ NA_real_
    ),
    
    # --- Interpolation method note ---
    interpolation_method = case_when(
      !is.na(petition_percentile) & petition_percentile <= 67 ~ "OFLC interpolated",
      !is.na(petition_percentile_acs)                        ~ "ACS interpolated",
      TRUE                                                    ~ NA_character_
    )
    
  ) %>%
  ungroup() %>%
  select(-is_fulltime, -ptile90_adj, -L4, -wage)
  
# Marge in native benchmarks for wage premium comparison 

premia_by_applicant <- read.csv("output/tables/h1b_with_native_comparisons_fy2022_2024.csv")

h1b_22_24 <- h1b_22_24 %>%
  left_join(premia_by_applicant, by = c("applicant_id" = "applicant_id")) %>%
  select(-prior_visa, -wage_level, -h1b_dependent, -employer_name, -puma_code,
         -employment_year, -registration_lottery_year.y, -X, -Soc_last1, -Soc_last2,
         -Soc_last3, -Match_Level, -Matched, Match_Level_Description, -Title, -Description,
         -h1b_wage)


# Output CSV with percentiles and native wage comparisons. 
write.csv(h1b_22_24, "h1b_with_percentiles_and_native_comps.csv")


