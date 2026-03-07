# Mincer Wage Calculation Methodology

This document explains how the pipeline calculates education- and experience-adjusted prevailing wages for H-1B petitions.

---

## Overview

The Department of Labor publishes prevailing wages by occupation and area, but these don't account for education or experience differences. This pipeline adjusts DOL wages to reflect individual worker qualifications.

**Three-step process:**
1. Start with DOL's occupational median wage (Level 3) for the specific occupation and area
2. Calculate education-experience adjustment ratios using statistical models
3. Multiply the ratio by the occupational median to get the worker-specific wage

---

## Mincer Model Specification

For each occupation, we estimate a wage equation using American Community Survey (ACS) data:

```
log(wage) = α + β₁·exp + β₂·exp² + β₃·exp³ + β₄·exp⁴ + Σγₖ·education_k + δₘ·metro_area + ε
```

**Variables:**
- `exp` = Years of potential experience (age - years of education - 6)
- `exp²`, `exp³`, `exp⁴` = Polynomial terms capturing nonlinear wage growth
- `education_k` = Dummy variables for education levels (Less than HS, High school, Some college, Associates, Bachelors, Masters, Professional degree, PhD)
- `metro_area` = Fixed effects for metropolitan areas (controls for geography)

The model is estimated once per occupation using all U.S. workers in that occupation, weighted by ACS survey weights (PERWT).

---

## Calculating Adjustment Ratios

For each combination of education and experience:

1. **Predict wages** across all metro areas using the fitted model
2. **Weight by area population** (sum of PERWT in each area)
3. **Calculate weighted average** across all areas
4. **Express as ratio** relative to the occupation's national median wage

Example: If a Bachelor's degree holder with 5 years experience earns 0.90x the occupation median, the ratio is 0.90.

These ratios are stored by (occupation, education, experience) and applied to H-1B petitions.

---

## Applying to H-1B Petitions

For each petition:

```
prevailing_wage = DOL_median[specific_occupation, metro_area] × ratio[occupation_group, education, experience]
```

**Key details:**
- **DOL median wages** are occupation-specific (e.g., Petroleum Engineers have different wages than Mechanical Engineers)
- **Ratios** are calculated at a more aggregated level (e.g., all engineers in the 17-21XX group share the same education-experience premiums)

**Example:**
- Worker: Software Developer (15-1252) with Bachelor's degree, 5 years experience, San Francisco
- DOL median for 15-1252 in San Francisco: $150,000
- Ratio for (1512XX, Bachelor's, 5 years): 0.85
- **Final wage: $150,000 × 0.85 = $127,500**

---

## Occupation Code Mapping

Data sources use different occupation coding systems:
- **FY2021-2022 petitions:** SOC 2010 codes
- **FY2023-2024 petitions:** SOC 2018 codes
- **ACS data:** OCCSOC 2018 codes

The pipeline uses crosswalk files to translate between these systems:
- `occupation_oflc_to_acs_crosswalk.csv` maps SOC 2018 → ACS 2018
- `fy2021_oflc_to_acs_crosswalk.csv` maps SOC 2010 → ACS 2018

Some occupations are aggregated (e.g., "17-21XX" represents all engineers in the 17-21 group) when ACS uses broader categories.

---

## Four Wage Levels

The pipeline calculates four prevailing wage levels based on occupational wage distribution percentiles:

- **50th percentile (pw_p50):** Median wage
- **62nd percentile (pw_p62):** Roughly equivalent to DOL Level 2
- **75th percentile (pw_p75):** Roughly equivalent to DOL Level 3
- **90th percentile (pw_p90):** Roughly equivalent to DOL Level 4

Each level uses a different scaling factor derived from the occupation's ACS wage distribution.

---

## Data Requirements

**ACS Microdata (IPUMS USA):**
- Years: 2019, 2021, 2022, 2023
- Variables: YEAR, AGE, INCWAGE, EMPSTAT, PERWT, EDUCD, OCCSOC, MET2013, PUMA, STATEFIP

**OFLC Prevailing Wage Data:**
- Annual wage level exports (FY 2021-2026)
- Contains DOL median wages by occupation, area, and year

**H-1B Petition Data:**
- FOIA petition records (FY 2021-2024)
- Labor Condition Applications (LCA data)
