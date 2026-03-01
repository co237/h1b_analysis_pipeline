# DOL NPRM Prevailing Wage Analysis

**An economic analysis of proposed reforms to the H-1B prevailing wage system**

## Overview

This project analyzes a forthcoming Department of Labor (DOL) rule that would reform how prevailing wages are set for H-1B and other employment-based visa programs. Under the current system, prevailing wages are based on employer job descriptions, which allows employers to understate position seniority and pay workers less. The proposed reform would instead tie prevailing wages to workers' actual qualifications (education and experience).

This analysis:
1. Reconstructs the universe of H-1B petitions filed in FY 2022-2024
2. Estimates worker-specific prevailing wages using a Mincer earnings model calibrated to American Community Survey (ACS) microdata
3. Simulates the effect of proposed wage threshold increases on petition underpayment rates

**Key Finding**: The analysis quantifies what share of H-1B petitions would still be underpaid (relative to comparable U.S. workers) under various proposed threshold scenarios.

## Project Structure

```
h1b_analysis_pipeline/
├── README.md                    # This file
├── config.R                     # Central configuration (paths, parameters)
├── run_all.R                    # Master script to run entire pipeline
│
├── scripts/                     # Analysis scripts (run in order 01-06)
│   ├── 01_data_cleaning.R      # Clean and merge FOIA + LCA data
│   ├── 02_geocode_to_pumas.R   # Map ZIP codes to Census PUMAs
│   ├── 03 interpolate wage percentiles.R  # Calculate petition percentiles
│   ├── 04 Calculate new prevailing wages.R # Estimate Mincer wage models
│   ├── 05 Apply new PWs to H1B petitions.R # Tag petitions with Mincer wages
│   └── 06 nprm_simulation.R    # Simulate NPRM policy effects
│
├── data/
│   ├── raw/                     # Source data (not in git)
│   ├── intermediate/            # Intermediate outputs
│   └── processed/               # Final processed datasets
│
└── output/
    ├── figures/                 # Generated charts
    └── tables/                  # Summary tables and exports
```

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/h1b_analysis_pipeline.git
cd h1b_analysis_pipeline
```

### 2. Get Required Data

You'll need several large datasets (~10 GB total):

- **H-1B FOIA petition data** (FY 2021-2024) from [Bloomberg](https://github.com/BloombergGraphics/2024-h1b-immigration-data)
- **Labor Condition Application (LCA) data** (2015-2024) from [DOL OFLC](https://www.dol.gov/agencies/eta/foreign-labor/performance)
- **ACS microdata** from [IPUMS USA](https://usa.ipums.org/) (years 2019-2023, must include `PUMA`, `OCCSOC`, `EDUCD`, `INCWAGE`)
- **OFLC prevailing wage data** (FY 2021-2025) from [DOL OFLC](https://www.dol.gov/agencies/eta/foreign-labor/performance)
- **Geographic and occupation crosswalks** (see `config.R` for details)

Place all files in `data/raw/` according to the structure in `config.R`.

### 3. Install R Packages

```r
install.packages(c("dplyr", "tidyr", "readr", "readxl", "ipumsr",
                   "stringr", "sf", "tidygeocoder", "fixest", "Hmisc"))
```

### 4. Run the Pipeline

**Option A: Run everything at once**
```r
source("run_all.R")
```

**Option B: Run scripts individually**
```r
source("scripts/01_data_cleaning.R")
source("scripts/02_geocode_to_pumas.R")
# ... and so on
```

## Pipeline Overview

### Step 1: Data Cleaning (`01_data_cleaning.R`)

**Input:**
- FOIA H-1B petition files (FY 2021-2024)
- LCA disclosure files (2015-2024)
- OFLC prevailing wage tables
- Geographic and occupation crosswalks

**Process:**
- Merges FOIA petitions with LCA applications to obtain SOC codes and wage levels
- Geocodes worksites to MSAs
- Crosswalks SOC 2010 codes to SOC 2018
- Matches occupation codes using string similarity and machine learning

**Output:**
- `data/intermediate/h1b_fy21_24_cleaned.csv` (~335 MB, 370K petitions)

**Runtime:** ~20-30 minutes

---

### Step 2: Geocode to PUMAs (`02_geocode_to_pumas.R`)

**Input:**
- Cleaned H-1B data from Step 1

**Process:**
- Downloads Census ZCTA-to-PUMA crosswalk files
- Maps worksite ZIP codes to 2020 and 2010 vintage PUMAs
- Uses largest geographic overlap for multi-PUMA ZIPs

**Output:**
- `data/processed/h1b_fy21_24_with_pumas.csv` (~350 MB)

**Runtime:** ~5 minutes

---

### Step 3: Interpolate Wage Percentiles (`03 interpolate wage percentiles.R`)

**Input:**
- H-1B data with PUMAs from Step 2
- ACS microdata (2021-2023)

**Process:**
- Uses OFLC wage levels (17th, 34th, 50th, 67th percentiles) to linearly interpolate each petition's percentile rank within its occupation
- Constructs synthetic 90th percentile using ACS for petitions above Level IV
- Calculates native worker wage benchmarks for comparison

**Output:**
- `h1b_with_percentiles_and_native_comps.csv` (~360 MB)

**Runtime:** ~15-20 minutes

---

### Step 4: Calculate Mincer Prevailing Wages (`04 Calculate new prevailing wages.R`)

**Input:**
- ACS microdata (2019-2023, 5-year pooled)
- OFLC prevailing wage tables (FY 2021-2025)
- Occupation crosswalk

**Process:**
- Estimates Mincer earnings equations (log wage ~ education + experience + experience² + ...) separately for each occupation
- Anchors wage level using OFLC Level 3 (occupation-area median)
- Creates lookup function: `predict_wage(soc_code, area, education, experience, year)` → 4 wage levels (p50, p62, p75, p90)

**Output:**
- Model objects stored in memory: `occ_area_models`, `oflc_bases`, `predict_wage()`
- Coefficient table: `output/tables/occ_model_coefficients.csv`

**Runtime:** ~30-45 minutes (Mincer estimation is CPU-intensive)

**Key Insight:** This alternative system ties wages to worker qualifications, not job descriptions.

---

### Step 5: Apply Mincer Wages to H-1B Petitions (`05 Apply new PWs to H1B petitions.R`)

**Input:**
- H-1B petitions from Step 3
- Mincer models from Step 4 (must be in memory)

**Process:**
- Calculates education and experience for each H-1B beneficiary
- Calls `predict_wage()` for each petition
- Tags each petition with four Mincer-based prevailing wages

**Output:**
- `h1b_with_mincer_wages.csv` (~370 MB, adds 4 wage columns)

**Runtime:** ~10-15 minutes

**Note:** Steps 4 and 5 must run in the same R session (Mincer models are held in memory).

---

### Step 6: NPRM Simulation (`06 nprm_simulation.R`)

**Input:**
- H-1B petitions with Mincer wages from Step 5

**Process:**
- User sets proposed percentile thresholds (e.g., Level I = 35th, Level II = 55th, Level III = 65th, Level IV = 80th)
- Filters to petitions that would meet new thresholds ("in scope")
- Calculates underpayment rate: share of in-scope petitions paid below their Mincer-based median (`pw_p50`)

**Output:**
- Console output showing underpayment rates by wage level and overall
- Optional: exports filtered datasets for further analysis

**Runtime:** < 1 minute

**Typical Use:** Run interactively, adjusting thresholds to test different policy scenarios

## Key Variables

| Variable | Description |
|----------|-------------|
| `petition_annual_pay_clean` | Annualized wage paid to H-1B worker |
| `PW_WAGE_LEVEL` | DOL-assigned prevailing wage level (I, II, III, IV) |
| `Level1_full` / `Level2_full` / etc. | OFLC wage thresholds (17th, 34th, 50th, 67th percentiles) |
| `petition_percentile_combined` | Worker's estimated percentile within occupation (from Step 3) |
| `pw_p50` / `pw_p62` / `pw_p75` / `pw_p90` | Mincer-based prevailing wages at 50th, 62nd, 75th, 90th percentiles (from Step 4/5) |

## Data Sources

- **H-1B FOIA Data**: [Bloomberg Graphics](https://github.com/BloombergGraphics/2024-h1b-immigration-data)
- **LCA Disclosure Data**: [DOL OFLC Performance Data](https://www.dol.gov/agencies/eta/foreign-labor/performance)
- **ACS Microdata**: [IPUMS USA](https://usa.ipums.org/)
- **OFLC Prevailing Wages**: [DOL OFLC](https://www.dol.gov/agencies/eta/foreign-labor/performance)
- **Geographic Crosswalks**: Census Bureau, HUD
- **Occupation Crosswalks**: BLS SOC

## Methodology Notes

### Why Mincer Equations?

The Mincer earnings equation is a standard labor economics model:

```
log(wage) = β₀ + β₁·education + β₂·experience + β₃·experience² + ... + ε
```

This model estimates how wages vary with education and experience *within* an occupation. By anchoring the wage level to OFLC's OES-based median and using Mincer to adjust for worker qualifications, we create a wage system that:
- Reflects actual labor market outcomes (ACS microdata)
- Varies by occupation and geography (OFLC median anchors)
- Rewards workers' human capital (education/experience adjustments)

### Two Wage Schedules

- **ALC (Standard)**: Used for most H-1B and PERM cases
- **EDC (ACWIA)**: Higher standard for H-1B dependent employers under the American Competitiveness and Workforce Improvement Act

### Year Matching

H-1B fiscal years (FY) correspond to employment years one year earlier:
- FY 2022 H-1Bs → employed in 2021 → compared to ACS 2021
- FY 2023 H-1Bs → employed in 2022 → compared to ACS 2022
- FY 2024 H-1Bs → employed in 2023 → compared to ACS 2023

## System Requirements

- **R**: 4.0.0 or higher
- **RAM**: 16 GB minimum (ACS microdata is large)
- **Disk**: 15-20 GB for data files
- **Runtime**: ~1.5-2 hours for full pipeline

## Troubleshooting

### Memory Issues

If Step 4 (Mincer estimation) runs out of memory:
- Close other applications
- Restart R: `.rs.restartR()`
- Run Steps 1-3, then 4-6 in separate sessions

### Missing Occupation Matches

Some petitions may not match to Mincer models if:
- SOC code is missing or invalid
- Occupation has < 100 ACS respondents (uses pooled national model as fallback)

### PUMA Geocoding Gaps

~5-10% of petitions may not match to PUMAs if:
- ZIP code is missing/invalid
- ZIP is not in Census ZCTA file (P.O. boxes, military addresses)

## Authors

**Institute for Progress** (2026)

Based on data cleaning code from Economic Innovation Group.

## License

[To be determined]

## Contact

For questions: connor@ifp.org

## Citation

If you use this analysis:

```
O'Brien, C. (2026). DOL NPRM Prevailing Wage Analysis.
Institute for Progress. GitHub repository.
```
