# H-1B Prevailing Wage Analysis Pipeline

**An economic analysis of H-1B prevailing wage determination and proposed DOL reforms**

## Overview

This project reconstructs the universe of H-1B petitions filed in FY 2022-2024 and estimates alternative prevailing wages using Mincer earnings models calibrated to American Community Survey (ACS) microdata. The pipeline enables simulation of different policy scenarios, including proposed Department of Labor (DOL) reforms to the prevailing wage system.

**Key Features:**
- Estimates worker-specific prevailing wages based on education and experience using Mincer earnings equations
- Accounts for geographic wage variation through area fixed effects and OFLC wage anchors
- Provides tools for simulating policy scenarios with custom percentile thresholds
- Processes ~273,000 H-1B petitions (FY 2022-2024) with 72.5% successful wage matching

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
│
├── scripts/                        # Analysis scripts (run in order 01-06)
│   ├── 01_data_cleaning.R          # Clean and merge FOIA + LCA data
│   ├── 02_geocode_to_pumas.R       # Map ZIP codes to Census PUMAs
│   ├── 03 interpolate wage percentiles.R  # Calculate petition percentiles
│   ├── 04 Calculate new prevailing wages.R # Estimate Mincer models
│   ├── 05 Apply new PWs to H1B petitions.R # Apply wages to petitions
│   └── 06 nprm_simulation.R        # Simulate NPRM policy effects
│
├── data/
│   ├── raw/                        # Source data (not in git, ~10 GB)
│   ├── intermediate/               # Intermediate outputs
│   └── processed/                  # Final processed datasets
│
└── output/
    ├── figures/                    # Generated charts
    └── tables/                     # Summary tables and exports
```

## Pipeline Steps

### Step 1: Data Cleaning (Script 01)
**Runtime:** ~20-30 minutes

Merges FOIA petition data with LCA applications to obtain occupation codes and wage levels. Standardizes all occupation codes to SOC 2018 using a two-stage crosswalk for FY2021-2022 data (SOC 2010 → SOC 2018 → ACS 2018).

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

**Hierarchical Fallback:** 6-digit SOC → 5-digit → 3-digit → 2-digit → pooled (minimum 100 observations)

**Output:**
- `data/processed/mincer_edu_exp_ratios.csv` (119,638 ratios for 377 occupations)
- Model objects stored in memory

### Step 5: Apply Mincer Wages to H-1B Petitions (Script 05)
**Runtime:** ~10-15 minutes

Applies Mincer-based prevailing wages to each petition using the formula:

```
pw_percentile = ratio[occupation, education, experience] × OFLC_Level3[occupation, area]
```

**Two-Stage Geographic Fallback:**
1. **Education/experience adjustments:** Use ratios from national model (place-invariant)
2. **Wage anchor:** Try MSA-level OFLC wage first, fall back to national if unavailable

**Output:** `data/processed/h1b_with_mincer_wages.csv` (~370 MB)

**Success Rate:** 198,407 petitions with valid Mincer wages (72.5% of total)

**Note:** Steps 4 and 5 should run in the same R session. Script 05 will automatically run Script 04 if needed.

### Step 6: NPRM Simulation (Script 06)
**Runtime:** < 1 minute

Simulates proposed DOL reforms by setting custom percentile thresholds for each wage level.

**User-Configurable Parameters:**
```r
pw_level_I_threshold   <- 34  # Proposed threshold for Level I
pw_level_II_threshold  <- 52  # Proposed threshold for Level II
pw_level_III_threshold <- 70  # Proposed threshold for Level III
pw_level_IV_threshold  <- 88  # Proposed threshold for Level IV
```

**Logic:**
1. Uses pre-calculated `petition_percentile_combined` to determine who qualifies
2. If `petition_percentile_combined >= threshold` → petition qualifies under proposed system
3. Among those who qualify, checks if `petition_wage < pw_p50` (Mincer median) → underpaid

**Output:** Console summary with qualification rates and underpayment statistics by wage level

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
3. Apply to petitions: `wage = ratio[occ, edu, exp] × OFLC_Level3[occ, area]`

### Occupation Code Harmonization

**Challenge:** Data spans multiple SOC vintages:
- FY2021-2022: SOC 2010 codes
- FY2023-2024: SOC 2018 codes
- ACS: Custom OCCSOC codes

**Solution:** Two-stage crosswalk system:
1. **FY2023+ → ACS:** Direct mapping using `occupation_oflc_to_acs_crowsswalk.csv`
2. **FY2021-2022 → ACS:** Three-stage mapping (SOC 2010 → SOC 2018 → ACS 2018) using `fy2021_oflc_to_acs_crosswalk.csv`

**Coverage:**
- FY2023+ crosswalk: 100% coverage
- FY2021-2022 crosswalk: 87.6% coverage (383,227 / 437,593 OFLC wage entries)

### Two-Stage Geographic Fallback

Mincer coefficients and OFLC wage anchors fall back independently:

1. **Mincer ratios:** Use national model ratios (place-invariant education/experience premiums)
2. **Wage anchor:** Try MSA-level OFLC wage → fall back to national if unavailable

**Example:** A junior software developer in Boise might use:
- National Mincer ratio for (Software Developer, Bachelor's, 3 years experience)
- MSA-level OFLC wage for Software Developers in Boise
- Final wage: `National_Ratio × Boise_OFLC_Wage`

## Results Summary

### Coverage Statistics
- **Total H-1B petitions:** 273,546 (FY 2022-2024)
- **Petitions with valid Mincer wages:** 198,407 (72.5%)
- **Occupations with Mincer models:** 377
- **Education-experience ratios:** 119,638
- **Model fallbacks to broader occupations:** 0 (all occupations fit at 6-digit level)

### NPRM Simulation Results (34th, 52nd, 70th, 88th Percentile Thresholds)
- **Petitions that qualify:** 23.8% (47,289 / 198,407)
- **Among qualified, underpaid vs Mincer median:** 36.9% (17,445 / 47,289)

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
Some petitions (~27.5%) don't receive Mincer wages due to:
- Missing required fields (education, MSA, occupation): 23.5%
- No matching OFLC/Mincer data despite complete fields: 4.0%

### Crosswalk Coverage Gaps
- FY2021-2022: 12.4% of OFLC codes couldn't be mapped to ACS 2018
- Affected petitions use petition-reported SOC codes when LCA merge fails

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
