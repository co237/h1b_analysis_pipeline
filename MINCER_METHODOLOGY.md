# Mincer Wage Calculation Methodology

**Technical Documentation for H-1B Prevailing Wage Estimation**

Last Updated: 2026-03-03

---

## Table of Contents

1. [Overview](#overview)
2. [National Mincer Models with Area Fixed Effects](#national-mincer-models-with-area-fixed-effects)
3. [Occupation Code Crosswalk System](#occupation-code-crosswalk-system)
4. [OFLC Wage Data Loading](#oflc-wage-data-loading)
5. [Mincer Model Estimation](#mincer-model-estimation)
6. [Applying Wages to H-1B Petitions](#applying-wages-to-h-1b-petitions)
7. [Complete Data Flow](#complete-data-flow)
8. [Design Decisions and Rationale](#design-decisions-and-rationale)

---

## Overview

### Goal

For each H-1B petition, calculate four prevailing wage levels (50th, 62nd, 75th, and 90th percentiles) that reflect what similarly-educated workers with similar experience earn in that occupation and area.

### Key Insight

The Department of Labor (DOL) publishes prevailing wages by occupation and area, but these are one-size-fits-all wages that don't account for education or experience differences. A PhD with 15 years of experience earns more than a Bachelor's degree holder with 2 years of experience, even in the same occupation and city. **Mincer equations** let us adjust the DOL wages to account for these individual differences.

### Three-Step Process

1. **OFLC Wage Anchor**: Start with DOL's Level 3 prevailing wage for the occupation and area
2. **Mincer Adjustment**: Use statistical models to calculate education-experience ratios
3. **Final Wage**: Multiply ratio by OFLC anchor to get petition-specific wage

---

## National Mincer Models with Area Fixed Effects

### Motivation

**Previous Approach (Area-Specific Models):**
- Estimated separate Mincer models for each occupation-area combination
- Required ≥100 observations per occupation per metro area
- Many occupation-area pairs had insufficient data → lower coverage
- Education/experience premiums varied by location (confounded by geography)

**New Approach (National Models with Area FE):**
- Estimate ONE national model per occupation with area fixed effects
- Only need ≥100 observations nationally (not per area)
- Education/experience premiums are place-invariant (human capital returns)
- Area fixed effects absorb location-based wage variation

### Model Specification

For each occupation, we estimate:

```
log(wage) = α + β₁·exp + β₂·exp² + β₃·exp³ + β₄·exp⁴ + Σγₖ·educationₖ + δₘ·MET2013 + ε
```

**Where:**
- `exp` = Years of potential experience (age - years of education - 6)
- `exp²`, `exp³`, `exp⁴` = Polynomial terms capturing nonlinear wage-experience profiles
- `educationₖ` = Dummy variables for 8 education levels (Associates is reference)
- `MET2013` = Fixed effects for metro areas
- `α`, `β`, `γ`, `δ` = Coefficients estimated from ACS data

**Education Categories:**
1. Less than HS
2. High school
3. Some college
4. Associates (reference category, omitted)
5. Bachelors
6. Masters
7. Professional degree
8. PhD

**Experience Polynomial:** The quartic (4th degree) polynomial captures the typical wage-experience profile:
- Wages rise quickly early in career (β₁ > 0)
- Growth slows with experience (β₂ < 0)
- May peak and decline near retirement (β₃, β₄ adjust curvature)

### Calculating Education-Experience Ratios

**Key Innovation:** Instead of using area-specific models, we calculate one set of ratios per occupation that are place-invariant.

**Process:**

1. **Fit national model with area FE** (using `fixest::feols`)
   ```r
   feols(
     log_incwage ~
       Years_pot_experience + I(Years_pot_experience^2) +
       I(Years_pot_experience^3) + I(Years_pot_experience^4) +
       highest_ed | MET2013,  # Area fixed effects
     data = occ_data,
     weights = ~PERWT
   )
   ```

2. **For each (education, experience) combination:**
   - Create prediction grid across ALL areas in the model
   - Predict log wage for each area
   - Convert to dollar wage: `wage = exp(log_wage)`
   - Weight by area population: `area_weight = sum(PERWT by area)`
   - Calculate weighted average: `avg_wage = Σ(wage × area_weight) / Σ(area_weight)`
   - Compare to national median: `ratio_p50 = avg_wage / median(occ_wages)`

3. **Store ratios** by (occupation, education, experience)

4. **Apply to petitions**: `wage = ratio[aggregated_ACS_code, edu, exp] × OFLC_Level3[specific_SOC, MSA]`
   - **OFLC wages**: Occupation-specific (17-2171 Petroleum Engineers ≠ 17-2141 Mechanical Engineers)
   - **Mincer ratios**: Aggregated by ACS code (all 17-21XX engineers share ratios)

### Why Weighted Averaging?

The weighted averaging approach captures the education and experience returns that are **not** due to place. By including area fixed effects in the model, we:

- **Absorb location-based wage levels** into the fixed effects (δₘ)
- **Isolate pure human capital returns** in the education/experience coefficients (β, γ)
- **Average across areas** to get place-invariant ratios that reflect skill premiums, not geography

**Example:** If software engineers with PhDs earn 1.5x the occupation median, this ratio applies whether they work in San Francisco or Omaha. The area-specific wage level comes from the OFLC anchor (which is higher in SF than Omaha).

### Benefits of This Approach

| Aspect | Old (Area-Specific) | New (National + Area FE) |
|--------|---------------------|--------------------------|
| **Models per occupation** | 10-20 (one per metro) | 1 (national with area FE) |
| **Ratio structure** | By (occupation, area) | By (occupation, education, experience) |
| **Coverage** | Lower (≥100 obs per area) | Higher (≥100 obs national) |
| **Complexity** | High (many models) | Low (one model per occ) |
| **Education/Experience premiums** | Vary by area | Place-invariant |

---

## Occupation Code Crosswalk System

### The Challenge

Our data spans multiple SOC (Standard Occupational Classification) vintages:

- **FY2021-2022 H-1B petitions**: Use SOC 2010 codes
- **FY2023-2024 H-1B petitions**: Use SOC 2018 codes
- **FY2021-2022 OFLC wages**: Published using SOC 2010 codes
- **FY2023+ OFLC wages**: Published using SOC 2018 codes
- **American Community Survey (ACS)**: Uses OCCSOC codes (2018 vintage)

We need **crosswalks** to translate between these code systems.

### Crosswalk #1: OFLC SOC 2018 → ACS 2018

**File:** `data/raw/occupation_oflc_to_acs_crowsswalk.csv`

**Purpose:** Maps FY2023+ OFLC wages (SOC 2018) to ACS 2018 occupation codes

**Structure:**
```
SocCode       ACS_OCCSOC     Match_Level    Description
-----------   -----------    ------------   ----------------------------
15-1252       15-1252        1              Exact match
17-2111       17-21XX        2              Aggregated (multiple → one)
11-1011       11-10XX        2              Aggregated to broader group
```

**Wildcards:**
- `XX`: Last 2 digits are wildcarded (aggregated group)
- `YY`: Alternative wildcard notation (normalized to `XX` in processing)

**Coverage:** 100% of FY2023+ OFLC codes

### Crosswalk #2: OFLC SOC 2010 → ACS 2018 (Two-Stage)

**File:** `data/raw/fy2021_oflc_to_acs_crosswalk.csv`

**Purpose:** Maps FY2021-2022 OFLC wages (SOC 2010) to ACS 2018 occupation codes

**Why Two Stages?** Direct SOC 2010 → ACS 2018 mapping would require manual matching across classification systems and time periods. Instead, we use Census's official crosswalks:

```
Stage 1: SOC 2010 → SOC 2018
   - Uses BLS official SOC 2010-to-2018 crosswalk
   - Maps old occupation codes to new structure
   - Some 2010 codes split into multiple 2018 codes

Stage 2: SOC 2018 → ACS 2018
   - Uses Census mapping from SOC 2018 to ACS OCCSOC
   - Handles aggregation where ACS uses broader categories
```

**Example Mapping:**
```
SOC 2010     →  SOC 2018     →  ACS 2018     Final Result
---------        ---------        ---------    -------------
17-2111          17-2051          17-20XX      Engineers (aggregated)
15-1131          15-1251          15-1251      Computer Programmers (exact)
```

**Coverage:** 87.6% of FY2021-2022 OFLC wage entries (383,227 / 437,593)

**Gap:** 12.4% of OFLC codes couldn't be mapped. Petitions with unmapped codes use petition-reported SOC codes when available.

### Critical Fix: Wildcard Normalization

**Problem:** The two crosswalks use different wildcard conventions:
- SOC 2018 crosswalk: Some codes use `YY` (e.g., "17-21YY")
- SOC 2010 crosswalk: All codes use `XX` (e.g., "17-21XX")

**Solution:** Normalize all wildcards by converting `YY` → `XX` before joining:
```r
ACS_OCCSOC = gsub("YY$", "XX", ACS_OCCSOC)
```

**Impact:** Without this fix, ~30% of petitions would fail to match due to wildcard mismatch.

---

## OFLC Wage Data Loading

### Data Source

**OFLC Prevailing Wage Determinations** (FY 2021-2025)
- Published annually by DOL Office of Foreign Labor Certification
- Contains OES-based wage levels by occupation, area, and wage level
- Two schedules: ALC (standard) and EDC (ACWIA for H-1B dependent employers)

### Loading Process (Script 04)

**For each fiscal year:**

1. **Read OFLC file** (CSV format)
2. **Annualize hourly wages**: Multiply by 2,080 hours/year
3. **Select crosswalk** based on year:
   - FY2021-2022: Use SOC 2010 crosswalk
   - FY2023+: Use SOC 2018 crosswalk
4. **Join with crosswalk** by SOC code
5. **Strip hyphens** from ACS_OCCSOC codes (e.g., "17-21XX" → "1721XX")
6. **Select relevant fields**: Area, SocCode, GeoLvl, Level3, ACS_OCCSOC

### SOC 2010 → SOC 2018 Conversion

**Challenge:** FY2021-2022 OFLC data uses SOC 2010 codes, but petitions use SOC 2018 codes.

**Example:**
```
SOC 2010 (OFLC FY2021)     →  SOC 2018 (Petitions)    OFLC Level 3 Wage
-----------------------        --------------------    ------------------
15-1132 (App Developers)   →  15-1252                 $101,837
15-1133 (Systems Dev)      →  15-1252                 $95,432
```

Multiple SOC 2010 codes map to a single SOC 2018 code.

**Solution:** Convert OFLC 2010 codes to 2018 format and aggregate when multiple 2010 codes map to one 2018 code:

```r
oflc_msa <- oflc_alc_all_years %>%
  left_join(soc_10_to_18_crosswalk, by = "SOC_2010_clean") %>%
  mutate(
    SOC_CODE_clean = ifelse(
      PW_year %in% c(2021, 2022) & !is.na(SOC_2018_clean),
      SOC_2018_clean,
      SOC_CODE_clean
    )
  ) %>%
  group_by(SOC_CODE_clean, MSA_code, PW_year) %>%
  summarise(Level3 = median(Level3, na.rm = TRUE))
```

**Key Point:** This conversion happens in the OFLC data, NOT in the petition data. Petitions always use 2018 SOC codes. The result is that each petition matches to its specific SOC code's OFLC wage (e.g., 15-1252), which may be an aggregate of multiple 2010 codes.

### Specific OFLC Wages × Aggregated Mincer Ratios

**Important Design Decision:** The final wage calculation combines:

1. **Occupation-specific OFLC wages** (17-2171 Petroleum Engineers ≠ 17-2141 Mechanical Engineers)
2. **Aggregated Mincer ratios** (all 17-21XX engineers share the same education-experience premiums)

**Example:**
```
Petroleum Engineer (17-2171), Houston, Bachelors, 10 years:
  OFLC_Level3[17-2171, Houston] = $130,000 (specific to petroleum engineers)
  Mincer_ratio[1721XX, Bachelors, 10 years] = 1.15 (shared by all 17-21XX engineers)
  Final wage = $130,000 × 1.15 = $149,500

Mechanical Engineer (17-2141), Houston, Bachelors, 10 years:
  OFLC_Level3[17-2141, Houston] = $95,000 (specific to mechanical engineers)
  Mincer_ratio[1721XX, Bachelors, 10 years] = 1.15 (same ratio as above)
  Final wage = $95,000 × 1.15 = $109,250
```

**Rationale:** This approach preserves occupation-specific wage differences from OFLC while applying consistent education-experience adjustments from ACS Mincer models. Some ACS codes aggregate multiple occupations (e.g., 1721XX includes all engineers), so we use the aggregated ACS code for Mincer ratios.

---

## Mincer Model Estimation

### Data Preparation (Script 04)

**Input:** ACS microdata (2019-2023 pooled, ~5-year sample)

**Filtering:**
```r
acs_data <- acs_data %>%
  filter(
    CITIZEN %in% c(1, 2),     # Native-born only
    EMPSTAT == "employed",    # Currently employed
    INCWAGE > 0,              # Positive wage income
    AGE >= 18, AGE <= 64      # Working age
  )
```

**Variable Creation:**
```r
Years_pot_experience = AGE - years_education - 6
Years_education = case_when(
  EDUCD >= 101 ~ 23,  # PhD
  EDUCD >= 114 ~ 20,  # Professional degree
  EDUCD >= 101 ~ 18,  # Master's
  EDUCD >= 101 ~ 16,  # Bachelor's
  EDUCD >= 81  ~ 14,  # Associates
  EDUCD >= 65  ~ 13,  # Some college
  EDUCD >= 63  ~ 12,  # High school
  TRUE ~ 10            # Less than HS
)
```

### Model Fitting

**For each occupation** (377 total):

1. **Filter to occupation**: Select all ACS workers in this occupation
2. **Check sample size**: Require ≥100 observations
3. **Fit model with area FE** using `fixest::feols`:
   ```r
   model <- feols(
     log_incwage ~
       Years_pot_experience + I(Years_pot_experience^2) +
       I(Years_pot_experience^3) + I(Years_pot_experience^4) +
       highest_ed | MET2013,  # Area fixed effects
     data = occ_data,
     weights = ~PERWT
   )
   ```
4. **Calculate ratios** for each (education, experience) combination
5. **Store ratios** in data frame

**Hierarchical Fallback** (if n < 100 at 6-digit level):
- 5-digit SOC group (e.g., 15-125X) with area FE
- 3-digit SOC group (e.g., 151XX) with area FE
- 2-digit SOC group (e.g., 15XXX) with area FE
- Fully pooled national model (all occupations) with area FE

**All models include area fixed effects** to ensure education and experience returns are place-invariant. Geographic wage variation is captured by the area-specific OFLC Level 3 wage anchor.

**Result:** 119,638 education-experience ratios across 377 occupations (no fallbacks needed in current data)

### Fixed-Effect Singletons

During estimation, you'll see messages like:
```
NOTE: 72 fixed-effect singletons were removed (72 observations).
```

**This is normal and expected.** It occurs when an area (MET2013) has only one observation for a particular occupation. The fixed effect for that area cannot be identified and is automatically dropped by `fixest`. This doesn't affect overall model quality.

**Important:** When computing weighted averages across areas (see step 4 above), `predict()` returns NA for areas where singleton fixed effects were removed. The ratio calculation code uses `na.rm = TRUE` in the `sum()` function to properly handle these NA predictions:

```r
weighted_avg <- sum(pred_wage_levels * pred_data$weight_prop, na.rm = TRUE)
```

Without `na.rm = TRUE`, even a single NA prediction would cause the entire weighted average to be NA, making the ratio NA. Since most occupations have at least one singleton area, this would result in 96.7% of ratios being NA (as occurred in an earlier implementation).

### Education Level Filtering

**Critical Implementation Detail:** Only use education levels that exist in the training data for each occupation.

**Why:** When predicting with a `fixest` model, if you try to use a factor level (like "Less than HS") that wasn't in the training data, `predict()` throws an error: `factor highest_ed has new level`.

**Solution:**
```r
education_levels_observed <- unique(occ_data$highest_ed[!is.na(occ_data$highest_ed)])
all_education_levels <- c("Less than HS", "High school", "Some college",
                          "Associates", "Bachelors", "Masters",
                          "Prof degree", "PhD")
education_levels <- intersect(all_education_levels, education_levels_observed)
```

Filter the prediction grid to only include education levels observed in the occupation's training data.

---

## Applying Wages to H-1B Petitions

### Data Loading (Script 05)

**Input:** `data/processed/h1b_with_percentiles_and_native_comps.csv`

This file contains:
- Petition details (occupation, location, salary)
- Education level codes
- Birth year (to calculate age and experience)
- `ACS_OCCSOC` code (added by Script 03)

### Petition Variable Calculation

```r
h1b_22_24 <- h1b_22_24 %>%
  mutate(
    # Map education code to years
    Years_education = case_when(
      petition_beneficiary_edu_code == "F" ~ 16,  # Bachelor's
      petition_beneficiary_edu_code == "G" ~ 18,  # Master's
      petition_beneficiary_edu_code == "I" ~ 23,  # PhD
      petition_beneficiary_edu_code == "H" ~ 20,  # Professional
      petition_beneficiary_edu_code == "D" ~ 14,  # Associates
      petition_beneficiary_edu_code == "C" ~ 13,  # Some college
      petition_beneficiary_edu_code == "B" ~ 12,  # High school
      TRUE ~ 10  # Less than HS
    ),

    # Calculate age and experience
    AGE = registration_lottery_year - registration_birth_year,
    Years_pot_experience = pmax(AGE - Years_education - 6, 0),

    # Determine OFLC year (year before lottery)
    PW_year = registration_lottery_year - 1,

    # Standardized education categories
    highest_ed = case_when(
      petition_beneficiary_edu_code == "F" ~ "Bachelors",
      petition_beneficiary_edu_code == "G" ~ "Masters",
      petition_beneficiary_edu_code == "I" ~ "PhD",
      petition_beneficiary_edu_code == "H" ~ "Prof degree",
      petition_beneficiary_edu_code == "D" ~ "Associates",
      petition_beneficiary_edu_code == "C" ~ "Some college",
      petition_beneficiary_edu_code == "B" ~ "High school",
      TRUE ~ "Less than HS"
    )
  )
```

### Critical Fixes for Matching

To ensure petitions match with OFLC data and Mincer ratios:

```r
# FIX 1: Strip hyphens
ACS_OCCSOC = gsub("-", "", ACS_OCCSOC)

# FIX 2: Normalize wildcards
ACS_OCCSOC = gsub("YY$", "XX", ACS_OCCSOC)
```

**Why these fixes matter:**
- Original crosswalk (Script 03) produced codes like "17-21YY" (hyphens, YY wildcard)
- OFLC loading strips hyphens → "1721XX"
- Without fixes: "1721YY" ≠ "1721XX" → join fails → NA wages
- With fixes: "1721YY" → "1721XX" → successful match

### Vectorized Wage Calculation

Rather than process 273,546 petitions individually, we identify ~69,000 unique combinations of (occupation, area, education, experience, year) and process those.

**Step 1: Join OFLC wages**
```r
# MSA-level wages only (no fallback)
unique_combos <- unique_combos %>%
  left_join(oflc_msa,
            by = c("ACS_OCCSOC", "MSA_code", "PW_year")) %>%
  rename(Level3_used = Level3)
```

**Coverage:**
- Only uses OFLC wages where they're officially published for the occupation-area combination
- If OFLC doesn't publish a wage (e.g., rare occupation in small metro), petition gets NA
- No fallback to national wages - this ensures we only produce wages with OFLC backing

**Step 2: Join Mincer ratios**
```r
# Round experience for matching
unique_combos <- unique_combos %>%
  mutate(Years_pot_experience_rounded = round(Years_pot_experience))

# Join ratios by (occupation, education, rounded experience)
unique_combos <- unique_combos %>%
  left_join(
    occ_edu_exp_ratios,
    by = c("ACS_OCCSOC" = "OCCSOC",
           "highest_ed" = "highest_ed",
           "Years_pot_experience_rounded" = "Years_pot_experience")
  )
```

**Step 3: Calculate final wages**
```r
unique_combos <- unique_combos %>%
  mutate(
    pw_p50 = round(Level3_used * ratio_p50),
    pw_p62 = round(Level3_used * ratio_p62),
    pw_p75 = round(Level3_used * ratio_p75),
    pw_p90 = round(Level3_used * ratio_p90),
    pw_oflc_median = Level3_used
  )
```

**Step 4: Join back to full petition data**
```r
h1b_22_24 <- h1b_22_24 %>%
  left_join(unique_combos,
            by = c("ACS_OCCSOC", "MSA_code", "highest_ed",
                   "Years_pot_experience", "PW_year"))
```

### Success Rates

**Final Statistics:**

| Metric | Count | Percentage |
|--------|-------|------------|
| Total H-1B petitions | 273,546 | 100% |
| Petitions with valid Mincer wages | 198,407 | 72.5% |
| Petitions with NA wages | 75,139 | 27.5% |

**Breakdown of NA wages:**
- Missing required fields (education, MSA, etc.): ~23.5%
- Have all fields but no matching data: ~4.0%

**Why some petitions get NA despite complete data:**
1. OFLC doesn't publish wages for that occupation-area-year
2. Occupation has <100 workers in ACS (no reliable model)
3. Crosswalk gaps (12.4% of FY2021-2022 codes unmapped)

---

## Complete Data Flow

```
1. FY2021-2022 OFLC Wages (SOC 2010)
   ↓ [Two-stage crosswalk: SOC 2010 → SOC 2018 → ACS 2018]
   ↓ [Strip hyphens: "17-21XX" → "1721XX"]
   → OFLC wages keyed by (ACS_OCCSOC, Area, Year)

2. FY2023+ OFLC Wages (SOC 2018)
   ↓ [Direct crosswalk: SOC 2018 → ACS 2018]
   ↓ [Strip hyphens: "15-1252" → "151252"]
   → OFLC wages keyed by (ACS_OCCSOC, Area, Year)

3. ACS Microdata (2019-2023)
   ↓ [Filter employed native workers, calculate experience]
   ↓ [Estimate Mincer equations with area FE by occupation]
   ↓ [Calculate education-experience ratios via weighted averaging]
   → Ratios keyed by (ACS_OCCSOC, Education, Experience)

4. H-1B Petitions
   ↓ [Get ACS_OCCSOC from crosswalk (has "YY" wildcards)]
   ↓ [Calculate education years, age, experience]
   ↓ [Strip hyphens: "17-21YY" → "1721YY"]
   ↓ [Normalize wildcards: "1721YY" → "1721XX"]
   → Petitions keyed by (ACS_OCCSOC, MSA, Education, Experience, Year)

5. JOINING
   ↓ [Join petitions with OFLC wages by (ACS_OCCSOC, MSA, Year)]
   ↓ [Join petitions with Mincer ratios by (ACS_OCCSOC, Education, Experience)]
   ↓ [Calculate: pw_percentile = ratio × OFLC_Level3]
   → Final wages: pw_p50, pw_p62, pw_p75, pw_p90

6. OUTPUT
   → data/processed/h1b_with_mincer_wages.csv
   → 198,407 petitions with valid wages (72.5% success rate)
```

---

## Design Decisions and Rationale

### Decision 1: National Models with Area FE (Not Area-Specific Models)

**Choice:** Estimate one national model per occupation with area fixed effects

**Rationale:**
- Better coverage (only need ≥100 observations nationally, not per area)
- Place-invariant education/experience premiums (human capital returns not confounded by geography)
- Simpler code (no area-specific fallback logic)
- More stable estimates (larger sample sizes)

**Trade-off:** Assumes education and experience premiums are constant across areas (only wage levels vary). This is a reasonable simplification supported by labor economics literature.

### Decision 2: Weighted Averaging by PERWT

**Choice:** Weight predicted wages by ACS person weights when calculating ratios

**Rationale:** PERWT represents population counts. Weighting by PERWT ensures ratios reflect the national distribution of workers, not just the ACS sample distribution.

### Decision 3: Two-Stage Crosswalk for FY2021-2022

**Choice:** SOC 2010 → SOC 2018 → ACS 2018 (two stages)

**Rationale:** Using Census's official crosswalks ensures we follow standard mappings. Direct SOC 2010 → ACS 2018 would require extensive manual matching.

**Trade-off:** 12.4% of codes couldn't be mapped, but this is unavoidable due to classification system changes.

### Decision 4: Median Aggregation for Multiple SOC → Same ACS

**Choice:** Take median when multiple SOC codes map to same ACS code

**Rationale:** Median is robust to outliers. Some occupations might have extreme wage values that would skew the mean.

### Decision 5: Round Experience for Matching

**Choice:** Round experience to nearest integer when joining ratios

**Rationale:** Ratios are stored for integer experience values (0, 1, 2, ..., 40). Rounding ensures successful joins while introducing negligible error.

### Decision 6: Use MET2013 (Not PUMA) for Area FE

**Choice:** Use MET2013 (metro area codes) as area fixed effects, not PUMA

**Rationale:**
- MET2013 aligns better with OFLC's MSA codes
- Provides metro-level fixed effects (more interpretable than PUMA)
- Still captures substantial geographic wage variation
- PUMA would be too granular (too many FEs, many singletons)

### Decision 7: No OFLC Geographic Fallback

**Choice:** Do not fall back to national OFLC wages when MSA-level wages are unavailable

**Rationale:**
- We only produce wages where OFLC publishes official prevailing wage data
- Falling back to national wages would create wage estimates for occupation-area combinations OFLC doesn't recognize
- Petitions in rare occupation-area combinations should receive NA, not fabricated wages
- This is more conservative and defensible from a policy perspective

---

## Appendix: Common Questions

### Q: Why use Level 3 as the OFLC anchor instead of Level 1 or 2?

**A:** Level 3 corresponds to the median wage in OFLC's methodology (50th percentile). This aligns well with our Mincer median ratios and provides a stable anchor point.

### Q: Do Mincer coefficients change across years?

**A:** No - Mincer equations are estimated once from pooled 2019-2023 ACS data. They capture the SHAPE of the education-experience wage curve, which is assumed stable. What changes by year is the OFLC Level 3 wage ANCHOR.

### Q: What happens if OFLC doesn't publish a wage for a specific occupation-area combination?

**A:** The petition receives NA wages. We do not fall back to national wages. This ensures we only produce wages where OFLC provides official prevailing wage data for that specific occupation-area combination.

### Q: Why quartic experience polynomial instead of linear or quadratic?

**A:** The quartic (4th degree) polynomial flexibly captures the hump-shaped wage-experience profile:
- Early career: rapid wage growth
- Mid-career: slower growth
- Late career: potential decline
- Quadratic would be too restrictive; higher-order polynomials risk overfitting

### Q: Could education/experience premiums actually vary by area?

**A:** Yes, in theory. However:
1. Estimating area-specific premiums requires much more data (often unavailable)
2. Literature suggests returns to education are relatively stable across locations
3. Our area FE approach captures the first-order effect (level differences)
4. Allowing varying slopes would require >100 observations per area per education level (infeasible)

---

**Scripts:** `04 Calculate new prevailing wages.R`, `05 Apply new PWs to H1B petitions.R`

**Author:** Institute for Progress (2026)

**Contact:** connor@ifp.org
