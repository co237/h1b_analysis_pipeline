# How Mincer-Adjusted Prevailing Wages Are Calculated

## Overview

This document explains the complete process of calculating Mincer-adjusted prevailing wages for H-1B petitions, from raw data to final wage estimates.

---

## The Big Picture

**Goal**: For each H-1B petition, calculate four prevailing wage levels (50th, 62nd, 75th, and 90th percentiles) that reflect what similarly-educated workers with similar experience earn in that occupation and area.

**Key Insight**: The Department of Labor (DOL) publishes prevailing wages by occupation and area, but these are one-size-fits-all wages that don't account for education or experience differences. A PhD with 15 years of experience earns more than a Bachelor's degree holder with 2 years of experience, even in the same occupation and city. **Mincer equations** let us adjust the DOL wages to account for these individual differences.

**Three-Step Process**:
1. **OFLC Wage Anchor**: Start with DOL's Level 3 prevailing wage for the occupation and area
2. **Mincer Adjustment**: Use statistical models to adjust the wage up or down based on education and experience
3. **Percentile Calculation**: Generate four wage levels corresponding to different skill/wage percentiles

---

## Part 1: Data Sources and Their Occupation Coding Systems

### The Challenge: Multiple SOC Code Vintages

Standard Occupational Classification (SOC) codes change over time as new occupations emerge and old ones evolve. Our data spans multiple SOC vintages:

- **FY2021-2022 H-1B petitions**: Use SOC 2010 codes (e.g., "17-2111")
- **FY2023-2024 H-1B petitions**: Use SOC 2018 codes (e.g., "17-2051")
- **FY2021-2022 OFLC wages**: Published using SOC 2010 codes
- **FY2023+ OFLC wages**: Published using SOC 2018 codes
- **American Community Survey (ACS) microdata**: Uses its own OCCSOC codes, which changed from 2013-2017 vintage to 2018 vintage

### The Solution: Crosswalks

We need **crosswalks** (mapping tables) to translate between these different code systems so we can:
1. Match H-1B petitions to OFLC wages
2. Match both to ACS microdata for Mincer model estimation

---

## Part 2: The Crosswalk System

### Crosswalk #1: OFLC SOC 2018 → ACS 2018 OCCSOC

**File**: `data/raw/occupation_oflc_to_acs_crowsswalk.csv`

**Purpose**: Maps FY2023+ OFLC wages (SOC 2018) to ACS 2018 occupation codes

**Example Mappings**:
```
SOC 2018      →  ACS 2018 OCCSOC  →  Description
-----------      ----------------     ---------------------------
15-1252       →  15-1252              Software Developers (exact match)
17-2111       →  17-21YY              Engineers (aggregated group)
11-1011       →  11-10XX              Chief Executives (aggregated)
```

**Key Feature**: Uses wildcard characters to handle aggregation:
- **XX**: Represents a group where last 2 digits are wildcarded
- **YY**: Represents a different aggregation level
- **XXX**: Three-digit wildcard for broader groups

### Crosswalk #2: OFLC SOC 2010 → ACS 2018 OCCSOC (Three-Stage)

**File**: `data/raw/fy2021_oflc_to_acs_crosswalk.csv`

**Purpose**: Maps FY2021-2022 OFLC wages (SOC 2010) to ACS 2018 occupation codes

**Why Three Stages?**: SOC 2010 → ACS 2018 is a big jump across two classification systems and two time periods. We do this in three steps for accuracy:

```
Stage 1: SOC 2010 (OFLC) → ACS 2013-2017 OCCSOC
   Uses historical Census crosswalk matching SOC 2010 to older ACS codes

Stage 2: ACS 2013-2017 → ACS 2018 OCCSOC
   Uses Census's own occupation code bridge between ACS vintages

Stage 3: Final mapping
   Combines stages 1 and 2 to produce SOC 2010 → ACS 2018
```

**Example**:
```
SOC 2010     Stage 1 →  ACS 2013    Stage 2 →  ACS 2018     Final Result
--------                ---------               ---------    -------------
17-2111                 1721XX                  17-21XX      SOC 2010 17-2111 → ACS 2018 "1721XX"
17-2112                 1721XX                  17-21XX      SOC 2010 17-2112 → ACS 2018 "1721XX"
17-2121                 172121                  17-2121      SOC 2010 17-2121 → ACS 2018 "172121"
```

**Coverage**: This crosswalk successfully maps 87.6% of FY2021 OFLC records (719 out of 821 distinct codes), covering 383,227 out of 437,593 wage entries.

### Critical Fix: Wildcard Standardization

**Problem Discovered**: The two crosswalks use different wildcard conventions:
- Original crosswalk: Uses "YY" for some groups (e.g., "17-21YY")
- FY2021-2022 crosswalk: Uses "XX" for all groups (e.g., "17-21XX")

**Solution**: Script 05 normalizes all wildcards by converting "YY" → "XX" before joining data, ensuring consistent matching across all years.

---

## Part 3: Loading and Preparing OFLC Wage Data

**Script**: `scripts/04 Calculate new prevailing wages.R`

### Step 3a: Load OFLC Files by Year

For each fiscal year (2021, 2022, 2023, 2025), we load two types of wage schedules:
- **ALC** (Standard prevailing wages): Used for most H-1B petitions
- **EDC** (ACWIA wages): Higher wages for H-1B dependent employers

### Step 3b: Crosswalk Selection Based on Year

```r
# FY2021-2022: Use SOC 2010 crosswalk (three-stage mapping)
oflc_2021 <- load_oflc("ALC_Export_FY2021.csv", use_2010_crosswalk = TRUE)

# FY2023+: Use SOC 2018 crosswalk (direct mapping)
oflc_2023 <- load_oflc("ALC_Export_FY2023.csv", use_2010_crosswalk = FALSE)
```

### Step 3c: Join OFLC Data with Crosswalk

The `load_oflc()` function:
1. Reads OFLC wage file
2. Annualizes hourly wages (multiply by 2,080 hours/year)
3. Joins with appropriate crosswalk by SOC code
4. **Strips hyphens** from ACS_OCCSOC codes (e.g., "17-21XX" → "1721XX")
5. Selects relevant columns: Area, SocCode, GeoLvl, Level3, ACS_OCCSOC

### Step 3d: Handling Multiple SOC Codes → Same ACS Code

**Problem**: Multiple detailed SOC codes can map to the same aggregated ACS code. For example:
```
SOC 2010        →  ACS 2018    OFLC Level 3 Wage
-----------        ---------    ------------------
17-2111         →  1721XX       $101,837 (Health/Safety Engineers)
17-2112         →  1721XX       $78,915  (Industrial Engineers)
17-2151         →  1721XX       $95,432  (Mining Engineers)
```

**Solution in Script 05**: When preparing OFLC data for joining, we aggregate by ACS_OCCSOC + Area + Year and take the **median** Level 3 wage when multiple SOC codes map to the same ACS code:

```r
oflc_msa <- oflc_alc_all_years %>%
  group_by(ACS_OCCSOC, MSA_code, PW_year) %>%
  summarise(
    Level3 = median(Level3, na.rm = TRUE),  # Take median wage
    .groups = "drop"
  )
```

This prevents duplicate rows and gives a representative wage for the aggregated occupation group.

---

## Part 4: Estimating Mincer Equations from ACS Microdata

**Script**: `scripts/04 Calculate new prevailing wages.R` (Section 3)

### What is a Mincer Equation?

A Mincer equation is a statistical model that predicts log wages based on education and experience:

```
log(wage) = α + β₁·exp + β₂·exp² + β₃·exp³ + β₄·exp⁴ + Σγₖ·educationₖ + ε

Where:
- exp = years of potential experience (age - years of education - 6)
- exp², exp³, exp⁴ = polynomial terms capturing non-linear wage growth
- educationₖ = dummy variables for each education level
- α, β, γ = coefficients estimated from ACS data
```

The quartic polynomial (exp⁴) captures the typical wage profile:
- Wages rise quickly early in career (β₁ > 0)
- Growth slows with experience (β₂ < 0)
- May peak and decline near retirement (β₃, β₄)

### ACS Data Preparation

1. **Load ACS microdata**: 2019-2023 pooled American Community Survey (5 years of data)
2. **Filter to employed workers**: EMPSTAT == "employed", INCWAGE > 0
3. **Calculate experience**: `Years_pot_experience = AGE - years_education - 6`
4. **Map to ACS 2018 OCCSOC codes**: Already in ACS data

### Model Hierarchy: From Granular to Pooled

For each occupation, we estimate models at multiple levels of geographic specificity and use the most granular one with sufficient data (≥100 observations):

```
1. Area-Specific Model
   - Occupation: 6-digit ACS OCCSOC (e.g., "151252")
   - Geography: Single metro area (e.g., San Francisco MSA)
   - Use when: ≥100 workers in this occupation in this metro

2. Occupation-Wide Model
   - Occupation: 6-digit ACS OCCSOC
   - Geography: All metros combined (national)
   - Use when: Not enough data for area-specific, but ≥100 workers nationally

3. 5-Digit SOC Group
   - Occupation: 5-digit group (e.g., "15125X")
   - Geography: National
   - Use when: Not enough for 6-digit, but ≥100 in broader group

[... continues through 2-digit and fully pooled ...]
```

**Result**: ~5,004 Mincer models stored in memory (486 occupations × multiple geography levels)

### Extracting the Key Ratio

For each Mincer model, we calculate the **ratio of median ACS wage to OFLC Level 3**:

```
ratio_p50 = median(predicted_wage_from_mincer) / OFLC_Level3
```

This ratio tells us: "ACS workers in this occupation earn X% of the OFLC Level 3 wage"

We also calculate ratios for other percentiles (p62, p75, p90).

---

## Part 5: Applying Mincer Wages to H-1B Petitions

**Script**: `scripts/05 Apply new PWs to H1B petitions.R`

### Step 5a: Load H-1B Petition Data

**Input**: `data/processed/h1b_with_percentiles_and_native_comps.csv`

This file was created by earlier pipeline scripts and contains:
- Petition details (occupation, location, salary)
- Education level
- Birth year (to calculate age and experience)
- **ACS_OCCSOC code** (added by Script 03 using the original crosswalk)

### Step 5b: Calculate Petition-Specific Variables

```r
h1b_22_24 <- h1b_22_24 %>%
  mutate(
    # Map education code to years of education
    Years_education = case_when(
      petition_beneficiary_edu_code == "F" ~ 16,  # Bachelor's
      petition_beneficiary_edu_code == "G" ~ 18,  # Master's
      petition_beneficiary_edu_code == "I" ~ 23,  # PhD
      ...
    ),

    # Calculate age and experience
    AGE = registration_lottery_year - registration_birth_year,
    Years_pot_experience = pmax(AGE - Years_education - 6, 0),

    # Determine which OFLC year to use (year before lottery)
    PW_year = registration_lottery_year - 1,

    # Map to standardized education categories
    highest_ed = case_when(
      petition_beneficiary_edu_code == "F" ~ "Bachelors",
      petition_beneficiary_edu_code == "G" ~ "Masters",
      petition_beneficiary_edu_code == "I" ~ "PhD",
      ...
    )
  )
```

### Step 5c: Critical Fixes for ACS_OCCSOC Matching

To ensure H-1B petitions match with OFLC data and Mincer models:

```r
# FIX 1: Strip hyphens (H-1B has "17-21YY", OFLC has "1721XX")
ACS_OCCSOC = gsub("-", "", ACS_OCCSOC)

# FIX 2: Normalize wildcards (H-1B has "YY", OFLC has "XX")
ACS_OCCSOC = gsub("YY$", "XX", ACS_OCCSOC)
```

**Why these fixes matter**:
- Original crosswalk (Script 03) produced codes like "17-21YY" (hyphens, YY wildcard)
- FY2021-2022 crosswalk produced codes like "17-21XX" (hyphens, XX wildcard)
- OFLC loading strips hyphens → "1721XX"
- Without fixes: "1721YY" ≠ "1721XX" → join fails, petitions get NA wages
- With fixes: "1721YY" → "1721XX" → successful match!

### Step 5d: Identify Unique Lookup Combinations

Rather than process all 273,546 petitions individually (slow), we identify unique combinations of:
- Occupation (ACS_OCCSOC)
- Geography (MSA_code)
- Education (highest_ed)
- Experience (Years_pot_experience)
- Year (PW_year)

**Result**: ~69,000 unique combinations instead of 273k rows (much faster!)

Petitions missing any required field receive NA wages (e.g., missing education code, missing MSA).

### Step 5e: Vectorized Join #1 - OFLC Level 3 Wages

Join unique combinations with OFLC wage data:

```r
# MSA-level wages (deduplicated by ACS_OCCSOC + MSA + Year)
oflc_msa <- oflc_alc_all_years %>%
  group_by(ACS_OCCSOC, MSA_code, PW_year) %>%
  summarise(Level3 = median(Level3))  # Handle multiple SOC → same ACS code

# National fallback wages
oflc_national <- oflc_alc_all_years %>%
  filter(GeoLvl == "N") %>%
  group_by(ACS_OCCSOC, PW_year) %>%
  summarise(Level3_national = median(Level3))

# Join: try MSA first, fall back to national if needed
unique_combos <- unique_combos %>%
  left_join(oflc_msa, by = c("ACS_OCCSOC", "MSA_code", "PW_year")) %>%
  left_join(oflc_national, by = c("ACS_OCCSOC", "PW_year")) %>%
  mutate(Level3_used = ifelse(!is.na(Level3), Level3, Level3_national))
```

**Geographic Hierarchy**:
1. Try to find MSA-level wage for this occupation
2. If not available, fall back to national wage for this occupation
3. If neither available, petition will get NA wage

### Step 5f: Vectorized Join #2 - Mincer Coefficients

Extract Mincer model coefficients into a flat table and join:

```r
# Extract coefficients from all 5,004 models
coef_df <- bind_rows(lapply(occ_area_models, function(m) {
  data.frame(
    ACS_OCCSOC = m$OCCSOC,
    model_area = m$Area,        # "NATIONAL" or metro code
    ratio_p50  = m$ratio_p50,   # Ratio for 50th percentile
    ratio_p62  = m$ratio_p62,
    ratio_p75  = m$ratio_p75,
    ratio_p90  = m$ratio_p90,
    b_intercept = m$coefs["(Intercept)"],
    b_exp1      = m$coefs["Years_pot_experience"],
    b_exp2      = m$coefs["I(Years_pot_experience^2)"],
    ... # education coefficients
  )
}))

# Join area-specific models first, fall back to national
unique_combos <- unique_combos %>%
  left_join(coef_df %>% filter(model_area != "NATIONAL"),
            by = c("ACS_OCCSOC", "MSA_code" = "model_area")) %>%
  left_join(coef_df %>% filter(model_area == "NATIONAL"),
            by = c("ACS_OCCSOC"),
            suffix = c("_area", "_nat"))
```

### Step 5g: Calculate Four Wage Levels

For each unique combination, calculate wages using the Mincer formula:

```r
unique_combos <- unique_combos %>%
  mutate(
    # Use area-specific coefficients if available, else national
    b0 = ifelse(!is.na(b_intercept_area), b_intercept_area, b_intercept_nat),
    b1 = ifelse(!is.na(b_exp1_area), b_exp1_area, b_exp1_nat),
    ... # all coefficients

    # Apply Mincer equation
    predicted_log_wage = b0 +
                        b1 * Years_pot_experience +
                        b2 * Years_pot_experience^2 +
                        b3 * Years_pot_experience^3 +
                        b4 * Years_pot_experience^4 +
                        b_ed * education_dummy,

    # Convert to dollar wage
    predicted_wage = exp(predicted_log_wage),

    # Scale to OFLC Level 3 using ratio
    pw_p50 = Level3_used * ratio_p50,
    pw_p62 = Level3_used * ratio_p62,
    pw_p75 = Level3_used * ratio_p75,
    pw_p90 = Level3_used * ratio_p90
  )
```

**The Formula in Words**:
1. Plug education and experience into Mincer equation → get predicted log wage
2. Exponentiate to get predicted dollar wage
3. Calculate ratio of predicted wage to OFLC anchor
4. Multiply OFLC Level 3 by ratio to get final prevailing wage at each percentile

### Step 5h: Join Back to Original Petitions

```r
h1b_22_24 <- h1b_22_24 %>%
  left_join(unique_combos,
            by = c("ACS_OCCSOC", "MSA_code", "highest_ed",
                   "Years_pot_experience", "PW_year"))
```

Each of the 273,546 petitions now has four wage levels (or NA if any required data was missing).

### Step 5i: Save Results

**Output**: `data/processed/h1b_with_mincer_wages.csv`

---

## Part 6: Results and Success Rates

**Final Statistics** (after all fixes):

| Metric                                    | Count     | Percentage |
|-------------------------------------------|-----------|------------|
| Total H-1B petitions                      | 273,546   | 100%       |
| Petitions with valid Mincer wages         | 194,778   | 71.2%      |
| Petitions with NA wages                   | 78,768    | 28.8%      |

**Breakdown of NA wages**:
- Missing required fields (education, MSA, etc.): 64,296 petitions (23.5%)
- Have all fields but no matching OFLC/Mincer data: 14,472 petitions (5.3%)

**Success rate among petitions with complete data**: 194,778 / 209,250 = **93.1%**

### Why Some Petitions Get NA Despite Having Complete Data

1. **OFLC doesn't publish wages for that occupation-area-year**: Rare occupations or small metros may not have wage data
2. **Mincer model doesn't exist**: Occupation has <100 workers in ACS, so no reliable model could be estimated
3. **Crosswalk gaps**: 12.4% of FY2021-2022 OFLC codes couldn't be mapped to ACS 2018

---

## Part 7: Key Design Decisions and Their Rationale

### Decision 1: Median vs. Mean When Aggregating OFLC Wages

**Choice**: Use median when multiple SOC codes map to same ACS code

**Rationale**: Median is robust to outliers. Some occupations might have extreme wage values that would skew the mean.

### Decision 2: Three-Stage Crosswalk for FY2021-2022

**Choice**: SOC 2010 → ACS 2013 → ACS 2018 (three stages)

**Rationale**: Direct SOC 2010 → ACS 2018 would require manual matching across classification systems and time periods. Using Census's own crosswalks ensures we follow their official mappings.

### Decision 3: Normalize "YY" → "XX" (Not Vice Versa)

**Choice**: Convert all "YY" wildcards to "XX"

**Rationale**: The FY2021-2022 crosswalk (majority of data) uses "XX". Converting "YY" → "XX" requires changing fewer codes.

### Decision 4: Area-Specific Models When Possible

**Choice**: Use metro-level Mincer models when ≥100 observations

**Rationale**: Wage structures vary by metro (e.g., software engineers earn more in San Francisco than Omaha). Area-specific models capture this variation.

### Decision 5: Store Coefficients, Not Pre-Computed Wages

**Choice**: Store Mincer coefficients in memory, compute wages on-the-fly

**Rationale**: Pre-computing all possible combinations of (occupation × area × education × experience × year) would create billions of rows. Storing coefficients and computing as needed is much more efficient.

---

## Summary: The Complete Flow

```
1. FY2021-2022 OFLC Wages (SOC 2010)
   ↓ [Three-stage crosswalk: SOC 2010 → ACS 2013 → ACS 2018]
   ↓ [Strip hyphens: "17-21XX" → "1721XX"]
   → OFLC wages keyed by (ACS_OCCSOC, Area, Year)

2. FY2023+ OFLC Wages (SOC 2018)
   ↓ [Direct crosswalk: SOC 2018 → ACS 2018]
   ↓ [Strip hyphens: "15-1252" → "151252"]
   → OFLC wages keyed by (ACS_OCCSOC, Area, Year)

3. ACS Microdata (2019-2023)
   ↓ [Filter employed workers, calculate experience]
   ↓ [Estimate Mincer equations by occupation × area]
   ↓ [Calculate ratios: ACS_median / OFLC_Level3]
   → Mincer coefficients + ratios keyed by (ACS_OCCSOC, Area)

4. H-1B Petitions
   ↓ [Get ACS_OCCSOC from original crosswalk - has "YY" wildcards]
   ↓ [Calculate education years, age, experience]
   ↓ [Strip hyphens: "17-21YY" → "1721YY"]
   ↓ [Normalize wildcards: "1721YY" → "1721XX"]
   → Petitions keyed by (ACS_OCCSOC, MSA, Education, Experience, Year)

5. JOINING
   ↓ [Join petitions with OFLC wages by (ACS_OCCSOC, MSA, Year)]
   ↓ [Join petitions with Mincer coefficients by (ACS_OCCSOC, MSA)]
   ↓ [Apply Mincer formula: predicted_wage = f(education, experience)]
   ↓ [Scale by ratio: pw_p50 = OFLC_Level3 × ratio_p50]
   → Final wages: pw_p50, pw_p62, pw_p75, pw_p90

6. OUTPUT
   → data/processed/h1b_with_mincer_wages.csv
   → 194,778 petitions with valid wages (71% success rate)
```

---

## Appendix: Common Troubleshooting

### Q: Why do some petitions get NA wages even though they have an occupation code?

**A**: Several possible reasons:
1. Missing education code → can't calculate years of education → can't plug into Mincer
2. Missing MSA code → can't look up area-specific wage
3. Occupation exists but OFLC doesn't publish wages for that area/year
4. Occupation has too few ACS workers (<100) to estimate reliable Mincer model
5. Occupation wasn't successfully mapped through crosswalk

### Q: Why use Level 3 as the OFLC anchor instead of Level 1 or 2?

**A**: Level 3 corresponds roughly to the median wage in OFLC's methodology (between experienced and highly experienced workers). This aligns well with using it as an anchor for Mincer adjustments.

### Q: Do the Mincer coefficients change across years?

**A**: No - the Mincer equations are estimated once from pooled 2019-2023 ACS data. They capture the SHAPE of the education-experience wage curve, which is assumed stable. What changes by year is the OFLC Level 3 wage ANCHOR, which reflects annual OES wage updates.

### Q: What happens if a petition's MSA doesn't have OFLC data?

**A**: We fall back to the national-level OFLC wage for that occupation. Similarly for Mincer models - we use national occupation-wide model if no area-specific model exists.

---

**Last Updated**: 2026-03-01
**Scripts**: `04 Calculate new prevailing wages.R`, `05 Apply new PWs to H1B petitions.R`
**Author**: Generated by Claude Code
