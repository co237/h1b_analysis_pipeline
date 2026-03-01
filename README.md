# DOL NPRM Prevailing Wage Analysis

**An economic analysis of proposed reforms to the H-1B prevailing wage system**

## Overview

This project analyzes proposed Department of Labor (DOL) reforms to the H-1B prevailing wage system. The pipeline reconstructs the universe of H-1B petitions filed in FY 2022-2024, estimates worker-specific prevailing wages using Mincer earnings models calibrated to American Community Survey (ACS) microdata, and provides tools for simulating different policy scenarios.

Users can:
1. Estimate alternative prevailing wages based on worker qualifications (education and experience) using Mincer earnings equations
2. Set custom percentile thresholds for wage levels (e.g., Level I = 45th percentile, Level II = 62nd percentile)
3. Simulate how different threshold combinations would affect petition underpayment rates

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
- Geographic crosswalks (ZIP-to-County, County-to-MSA, ZIP-to-CBSA)
- Occupation crosswalks (SOC 2010-to-2018, DOT-to-SOC)

**Process:**
- Merges FOIA petitions with LCA applications to obtain SOC codes and wage levels
- Geocodes worksites to MSAs using ZIP code crosswalks
- Standardizes occupation codes to SOC 2018 using the 2010-to-2018 crosswalk
- For petitions missing SOC codes, uses DOT-to-SOC crosswalk combined with string matching and machine learning to assign codes

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
- OFLC-to-ACS occupation crosswalk

**Process:**
- Tags each H-1B petition with its corresponding ACS occupation code using the OFLC-to-ACS crosswalk
- Uses OFLC wage levels (17th, 34th, 50th, 67th percentiles) to linearly interpolate each petition's percentile rank within its occupation
- Constructs synthetic 90th percentile using ACS wage distributions for petitions above Level IV (67th percentile)
- Calculates native worker wage benchmarks for comparison

**Output:**
- `data/processed/h1b_with_percentiles_and_native_comps.csv` (~360 MB)

**Runtime:** ~15-20 minutes

---

### Step 4: Calculate Mincer Prevailing Wages (`04 Calculate new prevailing wages.R`)

**Input:**
- ACS microdata (2019-2023, 5-year pooled)
- OFLC prevailing wage tables (FY 2021-2025)
- OFLC-to-ACS occupation crosswalk

**Process:**
- Uses OFLC-to-ACS crosswalk to link OFLC SOC codes (from wage tables) to ACS OCCSOC codes (for Mincer estimation)
- Estimates Mincer earnings equations for each occupation separately using native-born ACS workers
- **Functional form**: `log(wage) ~ exp + exp² + exp³ + exp⁴ + categorical_education`
  - Education is categorical (8 levels: Less than HS, High school, Some college, Associates [reference], Bachelors, Masters, Professional degree, PhD)
  - Experience enters as a quartic polynomial to capture nonlinear wage-experience profiles
  - Associates degree is the omitted reference category
- **Hierarchical fallback structure**: When sample size < 100 observations, falls back through:
  1. 6-digit SOC code (occupation-specific)
  2. 5-digit SOC group
  3. 3-digit SOC group
  4. 2-digit SOC group
  5. Fully pooled national model (all occupations)
- **Geographic hierarchy**: Area-specific models where data permits; otherwise national-level model
- Anchors wage level using OFLC Level 3 (occupation-area median from OES)
- Creates lookup function: `lookup_prevailing_wage(soc_code, area, education, experience, year)` → 4 wage levels (p50, p62, p75, p90)

**Output:**
- Model objects stored in memory: `occ_area_models`, `oflc_bases`, `lookup_prevailing_wage()`
- Coefficient table: `output/tables/occ_model_coefficients.csv`

**Runtime:** ~30-45 minutes (Mincer estimation is CPU-intensive)

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
- `data/processed/h1b_with_mincer_wages.csv` (~370 MB, adds 4 wage columns)

**Runtime:** ~10-15 minutes

**Note:** Steps 4 and 5 must run in the same R session (Mincer models are held in memory). Script 05 will automatically run Script 04 if needed.

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

### Mincer Earnings Equations

The Mincer earnings equation is a standard labor economics model relating wages to worker characteristics. The functional form used in this analysis is:

```
log(wage) = α + β₁·exp + β₂·exp² + β₃·exp³ + β₄·exp⁴ + Σγₖ·educₖ + ε
```

Where:
- Education enters as **categorical dummy variables** (8 levels: Less than HS, High school, Some college, Associates [reference], Bachelors, Masters, Professional degree, PhD)
- Experience enters as a **quartic polynomial** (exp, exp², exp³, exp⁴) to capture the nonlinear, "hump-shaped" wage-experience profile
- Associates degree is the omitted reference category

Models are estimated separately for each occupation using native-born ACS workers (2019-2023 pooled). The coefficients capture the returns to education and experience *within* each occupation. These coefficients are then used to adjust OFLC's OES-based wage anchors for individual worker qualifications.

### Hierarchical Fallback Structure

The pipeline uses a hierarchical approach to balance granularity with statistical reliability, falling back to broader samples when data is insufficient.

**Occupation hierarchy**: When sample size is insufficient (< 100 observations) at the 6-digit SOC level, the model falls back through progressively broader occupation groups:
1. 6-digit SOC code (e.g., 15-1252: Software Developers)
2. 5-digit SOC group (e.g., 15-125: Software and Web Developers)
3. 3-digit SOC group (e.g., 151: Computer Occupations)
4. 2-digit SOC group (e.g., 15: Computer and Mathematical)
5. Fully pooled national model (all occupations)

**Geographic area treatment**:

*Area-specific models (most granular)*:
- When an occupation-metro combination has n ≥ 100 ACS observations, a separate Mincer model is estimated using **only workers in that specific metro area**
- The data is **filtered** to that single metro (MET2013 == area_code) before estimation
- Geographic variation is controlled through sample restriction, not fixed effects
- Example: A model for Software Developers in San Francisco uses only San Francisco software developers

*National occupation models (fallback)*:
- When an occupation-metro combination has insufficient data (n < 100), the pipeline uses the occupation-wide model estimated across **all metros**
- No metro fixed effects are included in these broader models
- Example: If there aren't enough accountants in Boise, the national accountants model is used instead

**Two-stage geographic fallback**:

The Mincer coefficients and OES wage anchors fall back independently:

1. **Mincer coefficients** (education/experience adjustments):
   - Try area-specific model (occupation × metro) first
   - Fall back to national occupation model if area-specific unavailable

2. **OES wage anchor** (base wage level):
   - Try MSA-level OFLC Level 3 wage first
   - Fall back to national-level wage (GeoLvl = "N") if MSA-level unavailable

This means a petition might use:
- National Mincer coefficients × MSA wage anchor (most common fallback)
- Area-specific coefficients × national wage anchor (rare)
- Either × either, depending on data availability

**Practical example**: A junior software developer in Boise, Idaho might use:
- **Mincer coefficients**: Area-specific model for Software Developers in Boise (if n ≥ 100 in ACS)
- **Wage anchor**: National OES wage for Software Developers (if Boise doesn't have enough OES respondents)
- The education/experience adjustments reflect Boise's labor market, but the base wage level uses the national median

### Occupation Code Crosswalks

The pipeline integrates multiple data sources that use different occupation coding systems. Three major crosswalks reconcile these differences:

#### 1. OFLC-to-ACS Occupation Crosswalk (`occupation_oflc_to_acs_crowsswalk.csv`)

**Purpose**: Maps OFLC SOC codes (used in prevailing wage tables) to ACS OCCSOC codes (used in IPUMS microdata)

**Structure**:
- `SocCode`: OFLC SOC code with hyphen (e.g., "15-1252")
- `ACS_OCCSOC`: Corresponding ACS occupation code (e.g., "15-1252" or "15-12XX" for aggregated)
- `Soc_last1`, `Soc_last2`, `Soc_last3`: Fallback codes at progressively broader aggregation levels
- `Match_Level`: Quality indicator (1 = exact match, 2 = aggregated to broader category)
- `Match_Level_Description`: Human-readable match explanation (e.g., "Exact (SocCode)" or "Aggregated Level 1")

**How it's used**:
- Step 3 uses this crosswalk to tag H-1B petitions with ACS occupation codes for wage percentile interpolation
- Step 4 uses it to link OFLC prevailing wage anchors to the ACS-based Mincer models
- When OFLC uses granular codes not present in ACS, the crosswalk aggregates to the nearest ACS category
- Example: Multiple detailed OFLC education administrator codes (11-9031, 11-9032, 11-9033) all map to ACS code "11-9030" (education administrators, aggregated)

#### 2. SOC 2010 to SOC 2018 Crosswalk (`soc_2010_to_2018_crosswalk.xlsx`)

**Purpose**: Older LCA applications (pre-2024) use SOC 2010 codes; OFLC wage tables use SOC 2018. This crosswalk harmonizes them.

**Used in**: Step 1 (data cleaning) to standardize all occupation codes to SOC 2018 before merging with wage data.

#### 3. DOT to SOC Crosswalk (`DOT_to_ONET_SOC.xlsx`)

**Purpose**: Very old petitions may reference Dictionary of Occupational Titles (DOT) codes instead of SOC codes. This crosswalk maps DOT occupation categories to modern SOC codes.

**Used in**: Step 1 (data cleaning) in combination with string matching and machine learning to assign SOC codes to petitions missing them.

#### Geographic Crosswalks

Several geographic crosswalks are used in data cleaning and geocoding:
- **ZIP-to-County** (HUD USPS Crosswalk): Maps ZIP codes to county FIPS codes
- **County-to-MSA** (BLS area definitions): Maps counties to metropolitan statistical areas
- **ZIP-to-CBSA**: Direct ZIP to core-based statistical area mapping
- **ZCTA-to-PUMA** (Census Bureau): Maps ZIP Code Tabulation Areas to Public Use Microdata Areas for ACS data linkage

These are used in Steps 1-2 for worksite geocoding but don't affect wage estimation methodology.

### Two Wage Schedules

- **ALC (Standard)**: Used for most H-1B and PERM cases
- **EDC (ACWIA)**: Higher standard for H-1B dependent employers under the American Competitiveness and Workforce Improvement Act

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
