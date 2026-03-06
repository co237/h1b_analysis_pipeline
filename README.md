# H-1B Prevailing Wage Analysis Pipeline

**An economic analysis of H-1B prevailing wage determination and proposed DOL reforms**

## Overview

This project reconstructs the universe of H-1B petitions filed in FY 2022-2024 and estimates alternative prevailing wages using Mincer earnings models calibrated to American Community Survey (ACS) microdata. The pipeline enables simulation of different policy scenarios, including proposed Department of Labor (DOL) reforms to the prevailing wage system.

**Key Features:**
- Estimates worker-specific prevailing wages based on education and experience using Mincer earnings equations
- Combines occupation-specific OFLC Level 3 wages with aggregated Mincer ratios from national models
- Accounts for geographic wage variation through area fixed effects and MSA-specific OFLC anchors
- Provides tools for simulating policy scenarios with custom percentile thresholds
- Processes ~273,000 H-1B petitions (FY 2022-2024) with 76.5% successful wage matching

## Quick Start

### Prerequisites

- **R**: Version 4.0.0 or higher
- **RAM**: 16 GB minimum (ACS microdata requires substantial memory)
- **Disk Space**: 20 GB for data files
- **Runtime**: 1.5-2 hours for full pipeline

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/h1b_analysis_pipeline.git
   cd h1b_analysis_pipeline
   ```

2. **Install R packages**
   ```r
   install.packages(c("dplyr", "tidyr", "readr", "readxl", "ipumsr",
                      "stringr", "sf", "tidygeocoder", "fixest", "Hmisc"))
   ```

3. **Obtain required data** (see `DATA_SOURCES.md` for detailed instructions)
   - H-1B FOIA petition data from [Bloomberg Graphics](https://github.com/BloombergGraphics/2024-h1b-immigration-data)
   - Labor Condition Application (LCA) data from [DOL OFLC](https://www.dol.gov/agencies/eta/foreign-labor/performance)
   - ACS microdata from [IPUMS USA](https://usa.ipums.org/)
   - OFLC prevailing wage tables (FY 2021-2025)
   - Geographic and occupation crosswalks

4. **Run the pipeline**
   ```r
   source("run_all.R")  # Runs all scripts in sequence
   ```

## Project Structure

```
h1b_analysis_pipeline/
├── README.md                       # This file
├── MINCER_METHODOLOGY.md           # Detailed methodology documentation
├── DATA_SOURCES.md                 # Data download instructions
├── config.R                        # Central configuration
├── run_all.R                       # Master execution script
├── lookup_wages.R                  # Fast wage lookup function
│
├── scripts/                        # Analysis scripts (run in order 01-07)
│   ├── 01_data_cleaning.R          # Clean and merge FOIA + LCA data
│   ├── 02_geocode_to_pumas.R       # Map ZIP codes to Census PUMAs
│   ├── 03 interpolate wage percentiles.R  # Calculate petition percentiles
│   ├── 04 Calculate new prevailing wages.R # Estimate Mincer models
│   ├── 05 Apply new PWs to H1B petitions.R # Apply wages to petitions
│   ├── 06 nprm_simulation.R        # Simulate NPRM policy effects
│   └── 07 interactive wage lookup.R # User-friendly wage calculator
│
├── docs/
│   └── data_directories/           # Documentation for data folders
│       ├── RAW_DATA.md             # What's in data/raw/
│       ├── INTERMEDIATE_DATA.md    # What's in data/intermediate/
│       ├── PROCESSED_DATA.md       # What's in data/processed/
│       └── README.md               # Data directory overview
│
├── data/                           # Symlinked to Google Drive
│   ├── raw/                        # Source data (~7 GB)
│   ├── intermediate/               # Intermediate outputs (~658 MB)
│   └── processed/                  # Final processed datasets (~350 MB)
│
└── output/                         # Symlinked to Google Drive
    ├── figures/                    # Generated charts
    └── tables/                     # Summary tables and exports
```

## Pipeline Steps

### Step 1: Data Cleaning (Script 01)
**Runtime:** ~20-30 minutes

Merges FOIA petition data with LCA applications to obtain occupation codes and wage levels. Standardizes all occupation codes using crosswalks:
- **FY2023+**: Direct SOC 2018 → ACS 2018 mapping
- **FY2021-2022**: Two-stage SOC 2010 → SOC 2018 → ACS 2018 mapping

**Input:**
- H-1B FOIA petition files (FY 2021-2024)
- LCA disclosure files (2015-2024)
- SOC 2010 to SOC 2018 crosswalk

**Output:** `data/intermediate/h1b_fy21_24_cleaned.csv` (~335 MB, 370K petitions)

### Step 2: Geocode to PUMAs (Script 02)
**Runtime:** ~5 minutes

Maps worksite ZIP codes to Census Public Use Microdata Areas (PUMAs) using ZCTA crosswalk files for both 2020 and 2010 vintages.

**Output:** `data/processed/h1b_fy21_24_with_pumas.csv` (~350 MB)

### Step 3: Interpolate Wage Percentiles (Script 03)
**Runtime:** ~15-20 minutes

Calculates each petition's estimated percentile rank within its occupation using OFLC wage levels as anchors. Uses linear interpolation between wage levels (17th, 34th, 50th, 67th percentiles) and constructs synthetic 90th percentile using ACS wage distributions.

**Output:** `data/processed/h1b_with_percentiles_and_native_comps.csv` (~360 MB)

### Step 4: Calculate Mincer Prevailing Wages (Script 04)
**Runtime:** ~30-45 minutes

**Core Innovation:** Estimates national Mincer earnings equations with area fixed effects for 377 occupations using pooled ACS microdata (2019-2023).

**Methodology:**
- Fits one national model per occupation: `log(wage) ~ exp + exp² + exp³ + exp⁴ + education | area_FE`
- Education enters as categorical (8 levels: Less than HS, High school, Some college, Associates, Bachelors, Masters, Professional degree, PhD)
- Experience enters as quartic polynomial to capture nonlinear wage-experience profiles
- Area fixed effects absorb location-based wage variation
- Calculates education-experience ratios by predicting wages across all areas, weighting by ACS person weights (PERWT), and comparing to national median
- Stores one ratio per (occupation, education, experience) combination

**Hierarchical Fallback:** 6-digit SOC → 5-digit → 3-digit → 2-digit → pooled (minimum 100 observations, all models include area FE)

**Output:**
- `data/processed/mincer_edu_exp_ratios.csv` (119,638 ratios for 377 occupations)
- Model objects stored in memory

### Step 5: Apply Mincer Wages to H-1B Petitions (Script 05)
**Runtime:** ~10-15 minutes

Applies Mincer-based prevailing wages to each petition by combining:
1. **Specific OFLC wages**: Each occupation's Level 3 wage in each MSA (e.g., 17-2171 Petroleum Engineers in Houston)
2. **Aggregated Mincer ratios**: Education-experience premiums from national models (e.g., all 17-21XX engineers share the same ratios)

**Formula:**
```
pw_p50 = OFLC_Level3[specific_SOC, MSA] × ratio_p50[aggregated_ACS_code, education, experience]
```

**Example:**
- **Petroleum Engineers (17-2171)** and **Mechanical Engineers (17-2141)** have different OFLC wages
- Both use the same Mincer ratios from the **1721XX Engineers** model
- Result: Occupation-specific wages adjusted for individual education/experience

**SOC Code Handling:**
- FY2021-2022 OFLC data uses SOC 2010 codes (e.g., 15-1132, 15-1133)
- Script converts to SOC 2018 format (e.g., 15-1252) and aggregates when multiple 2010 codes map to one 2018 code
- Ensures petitions match correctly across all fiscal years

**Output:** `data/processed/h1b_with_mincer_wages.csv` (~370 MB)

**Success Rate:** 209,129 petitions with valid Mincer wages (76.5% of total)

**Note:** Steps 4 and 5 should run in the same R session. Script 05 will automatically run Script 04 if needed.

### Step 6: NPRM Simulation (Script 06)
**Runtime:** < 1 minute

Simulates proposed DOL reforms by setting custom percentile thresholds for each wage level.

**User-Configurable Parameters:**
```r
pw_level_I_threshold   <- 35  # Proposed threshold for Level I (2021 Rule)
pw_level_II_threshold  <- 53  # Proposed threshold for Level II (2021 Rule)
pw_level_III_threshold <- 72  # Proposed threshold for Level III (2021 Rule)
pw_level_IV_threshold  <- 90  # Proposed threshold for Level IV (2021 Rule)
```

**Logic:**
1. Uses pre-calculated `petition_percentile_combined` to determine who qualifies
2. If `petition_percentile_combined >= threshold` → petition qualifies under proposed system
3. Among those who qualify, checks if `petition_wage < pw_p50` (Mincer median) → underpaid

**Output:** Console summary with qualification rates and underpayment statistics by wage level

### Step 7: Interactive Wage Lookup (Script 07)
**Runtime:** ~2 seconds (after Script 04 has run)

User-friendly calculator for Experience Benchmarking prevailing wages. Simply edit parameters at the top of the script and run.

**How to Use:**
1. Open `scripts/07 interactive wage lookup.R` in RStudio
2. Edit the USER INPUTS section (lines 26-44):
   ```r
   SOC_CODE <- "15-1252"      # Occupation
   EDUCATION <- "Bachelors"   # Education level
   EXPERIENCE <- 5            # Years of experience
   MSA_CODE <- "41860"        # San Francisco
   YEAR <- 2023               # Fiscal year
   WAGE_TYPE <- "ALC"         # Standard or "EDC" for ACWIA
   ```
3. Run the entire script (Ctrl/Cmd + Shift + Enter)

**Output:** Formatted display showing:
- Occupational median (OFLC Level 3)
- Four Experience Benchmarking wage levels (50th, 62nd, 75th, 90th percentiles)
- Education-experience adjustment ratio
- Comparison to typical worker (e.g., "earns 21.4% less than typical worker")
- Percentile scaling factors

**For Programmatic Use:** Use `lookup_wages.R` directly (see next section)

## Interactive Wage Lookup

Two ways to query Experience Benchmarking prevailing wages:

### Option 1: User-Friendly Script (Script 07)

Best for **occasional lookups** in RStudio:

```r
# Open scripts/07 interactive wage lookup.R
# Edit parameters at top, then run script
# Get formatted output with explanations
```

See [Step 7](#step-7-interactive-wage-lookup-script-07) above for details.

### Option 2: Programmatic Function (lookup_wages.R)

Best for **batch queries** or **integration** into other code:

```r
# Load the function and data (fast - ~2 seconds)
source("lookup_wages.R")

# Query a specific scenario
result <- get_prevailing_wages(
  soc_code = "15-1252",        # Software Developers
  education = "Bachelors",      # Bachelor's degree
  experience = 5,               # 5 years experience
  msa_code = "41860",          # San Francisco MSA
  year = 2023,                 # Fiscal year 2023
  wage_type = "ALC"            # Standard (or "EDC" for ACWIA)
)

# Access results
result$status       # "success" or "error"
result$oflc_level3  # OFLC Level 3 wage (occupational median)
result$pw_p50       # Mincer wage at 50th percentile
result$pw_p62       # Mincer wage at 62nd percentile
result$pw_p75       # Mincer wage at 75th percentile
result$pw_p90       # Mincer wage at 90th percentile
```

**Parameters:**
- `soc_code`: 6-digit SOC code (with or without hyphen, SOC 2010 or 2018)
- `education`: "Less than HS", "High school", "Some college", "Associates", "Bachelors", "Masters", "Prof degree", "PhD"
- `experience`: Years of experience (0-50)
- `msa_code`: MSA/area code
- `year`: Fiscal year (2021-2026)
- `wage_type`: "ALC" (standard) or "EDC" (ACWIA)

**Data Efficiency:** Uses RDS format (instant loading, no massive CSV files required)

## Key Variables

| Variable | Description |
|----------|-------------|
| `petition_annual_pay_clean` | Annualized wage paid to H-1B worker |
| `PW_WAGE_LEVEL` | DOL-assigned prevailing wage level (I, II, III, IV) |
| `ACS_OCCSOC` | ACS occupation code (harmonized across years) |
| `petition_percentile_combined` | Worker's estimated percentile within occupation |
| `pw_p50` / `pw_p62` / `pw_p75` / `pw_p90` | Mincer-based prevailing wages at 50th, 62nd, 75th, 90th percentiles |
| `pw_oflc_median` | OFLC Level 3 wage anchor |
| `Years_pot_experience` | Years of potential experience (age - education years - 6) |
| `highest_ed` | Standardized education category |

## Methodology Overview

### National Mincer Models with Area Fixed Effects

**Key Innovation:** Instead of estimating separate Mincer models for each occupation-area combination, we fit ONE national model per occupation that includes area fixed effects:

```
log(wage) = α + β₁·exp + β₂·exp² + β₃·exp³ + β₄·exp⁴ + Σγₖ·educationₖ + δₘ·area_FE + ε
```

**Why This Approach?**
- **Place-invariant human capital returns:** Education and experience coefficients capture "pure" returns after controlling for geography
- **Better coverage:** Only need ≥100 observations nationally (not per area)
- **More stable estimates:** Larger sample sizes reduce coefficient variance
- **Simpler code:** Eliminates complex area-specific fallback logic

**How It Works:**
1. Fit national model with area FE: `feols(log_wage ~ exp + exp² + exp³ + exp⁴ + education | area, weights = PERWT)`
2. For each (education, experience) combination:
   - Predict wages across ALL areas in the model
   - Weight by PERWT (ACS person weights summed by area)
   - Calculate weighted average predicted wage
   - Compare to national median → store ratio
3. Apply to petitions: `wage = ratio[aggregated_ACS_code, edu, exp] × OFLC_Level3[specific_SOC, MSA]`
   - **OFLC wages are occupation-specific** (17-2171 Petroleum Engineers ≠ 17-2141 Mechanical Engineers)
   - **Mincer ratios are aggregated** (all 17-21XX engineers share the same education-experience premiums)

### Occupation Code Harmonization

**Challenge:** Data spans multiple SOC vintages:
- FY2021-2022: SOC 2010 codes
- FY2023-2024: SOC 2018 codes
- ACS: Custom OCCSOC codes

**Solution:** Two-stage crosswalk system:
1. **FY2023+ → ACS:** Direct mapping using `occupation_oflc_to_acs_crowsswalk.csv`
2. **FY2021-2022 → ACS:** Two-stage mapping (SOC 2010 → SOC 2018 → ACS 2018)
   - Uses official Census SOC 2010-to-2018 crosswalk
   - Then maps to ACS 2018 using existing crosswalk
   - Includes manual mappings for consolidated IT occupations

**Coverage:**
- FY2023+ crosswalk: 100% coverage (848 SOC 2018 codes)
- FY2021-2022 crosswalk: 100% coverage (892 SOC 2010 codes, improved from previous 87.6%)

### Geographic Handling

The wage calculation combines national and area-specific components:

1. **Mincer ratios:** Place-invariant education/experience premiums from national models
2. **OFLC wage anchor:** Area-specific wage levels from OFLC prevailing wage tables

**Example:** A junior software developer (15-1252) in Boise uses:
- National Mincer ratio for (151252, Bachelor's, 3 years experience) = 0.85
- Boise MSA OFLC Level 3 wage for SOC 15-1252 = $110,000
- Final wage: `0.85 × $110,000 = $93,500`

**Important:** If OFLC doesn't publish a wage for a specific SOC-area combination (e.g., rare occupation in small metro), the petition receives NA. This ensures we only produce wages where OFLC provides official prevailing wage data for that specific occupation.

## Results Summary

### Coverage Statistics
- **Total H-1B petitions:** 273,546 (FY 2022-2024)
- **Petitions with valid Mincer wages:** 209,129 (76.5%)
- **Occupations with Mincer models:** 377
- **Education-experience ratios:** 119,638
- **Unique SOC codes in petitions:** 378
- **Unique ACS codes (aggregated for Mincer):** 213

### Policy Simulation Results
The pipeline supports simulation of different wage threshold scenarios:
- **Status Quo (17th, 34th, 50th, 67th)**: Current OFLC system
- **2021 Rule (35th, 53rd, 72nd, 90th)**: Proposed DOL reform thresholds

## Detailed Methodology Documentation

For detailed technical documentation, see:
- **`MINCER_METHODOLOGY.md`**: Complete explanation of Mincer estimation, crosswalk system, and wage calculation
- **`DATA_SOURCES.md`**: Data download instructions and file structure

## System Requirements

- **R Version:** 4.0.0 or higher
- **RAM:** 16 GB minimum (32 GB recommended for smooth operation)
- **Disk Space:**
  - Data files: ~10 GB
  - Intermediate outputs: ~5 GB
  - Free space for processing: ~5 GB
- **Runtime:** Full pipeline takes 1.5-2 hours on a modern laptop

## Troubleshooting

### Memory Issues
If Step 4 (Mincer estimation) runs out of memory:
```r
# Restart R session
.rs.restartR()

# Run scripts in batches
source("scripts/01_data_cleaning.R")
source("scripts/02_geocode_to_pumas.R")
source("scripts/03 interpolate wage percentiles.R")

# New session
source("scripts/04 Calculate new prevailing wages.R")
source("scripts/05 Apply new PWs to H1B petitions.R")
```

### Missing Occupation Matches
Some petitions (~23.5%) don't receive Mincer wages due to:
- Missing required fields (education primarily): 23.5%
- No matching OFLC/Mincer data despite complete fields: <0.1%

The vast majority of missing wages are due to missing education codes in the petition data, not failures in the matching logic.

### Crosswalk Coverage
- **Current (two-stage)**: 100% coverage for both FY2021-2022 and FY2023+
- All OFLC SOC codes successfully map to ACS occupation codes
- Previous approach had 87.6% coverage; new two-stage crosswalk achieves 100%

### PUMA Geocoding Gaps
~5-10% of petitions may not match to PUMAs if:
- ZIP code is missing or invalid
- ZIP is not in Census ZCTA file (P.O. boxes, military addresses)

## Authors

**Institute for Progress** (2026)

Connor O'Brien (connor@ifp.org)

Based on data cleaning code from Economic Innovation Group.

## Citation

If you use this analysis:

```
O'Brien, C. (2026). H-1B Prevailing Wage Analysis Pipeline.
Institute for Progress. GitHub repository.
https://github.com/yourusername/h1b_analysis_pipeline
```

## License

[To be determined]

## Contact

For questions or data access:
- Email: connor@ifp.org
- GitHub Issues: [Open an issue](https://github.com/yourusername/h1b_analysis_pipeline/issues)

## Acknowledgments

- **Data Sources:** Bloomberg Graphics, DOL OFLC, IPUMS USA, Bureau of Labor Statistics
- **Methodology:** National Mincer models with area fixed effects approach
- **Code Development:** Economic Innovation Group (data cleaning), Institute for Progress (Mincer estimation and simulation)
