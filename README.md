# H-1B Wage Premium Analysis Pipeline

A comprehensive R-based pipeline for analyzing wage premiums of H-1B visa holders compared to native-born workers, with multiple control configurations including geographic (PUMA) controls.

## Overview

This project integrates three main components:
1. **Data Cleaning**: Processes H-1B FOIA petition data and Labor Condition Application (LCA) data
2. **Geocoding**: Maps H-1B worksite addresses to Public Use Microdata Areas (PUMAs)
3. **Wage Premium Analysis**: Compares H-1B wages to native-born worker wages with various control configurations

## Repository Structure

```
h1b_analysis_pipeline/
├── README.md                      # This file
├── config.R                       # Central configuration file
├── run_pipeline.R                 # Main pipeline orchestration script
├── .gitignore                     # Git ignore rules
│
├── scripts/                       # Analysis scripts (run in order)
│   ├── 01_data_cleaning.R        # Clean and merge FOIA/LCA data
│   ├── 02_geocode_to_pumas.R     # Geocode ZIP codes to PUMAs
│   └── 03_wage_premium_analysis.R # Wage premium analysis with controls
│
├── data/                          # Data files (not tracked in git)
│   ├── raw/                       # Original data files
│   │   ├── TRK_13139_FY20XX.csv  # FOIA H-1B petition data
│   │   ├── LCA_Data/             # Labor Condition Applications
│   │   ├── usa_00061.xml         # ACS IPUMS DDI file
│   │   ├── usa_00061.dat.gz      # ACS IPUMS microdata
│   │   ├── soc_2018_definitions.xlsx
│   │   ├── ZIP_COUNTY_122024.xlsx
│   │   ├── ZIP_CBSA_122024.xlsx
│   │   ├── area_definitions_m2023.xlsx
│   │   ├── soc_2010_to_2018_crosswalk.xlsx
│   │   ├── DOT_to_ONET_SOC.xlsx
│   │   ├── OFLC_Wages_2024-25/   # OFLC wage level data
│   │   └── census_crosswalks/    # Auto-downloaded by script
│   │
│   ├── intermediate/              # Intermediate outputs
│   │   ├── h1b_fy21_24_cleaned.csv
│   │   └── dot_matching/         # Occupation matching files
│   │
│   └── processed/                 # Final processed data
│       └── h1b_fy21_24_with_pumas.csv
│
└── output/                        # Analysis outputs
    ├── figures/                   # Generated plots
    └── tables/                    # Generated tables
```

## Data Requirements

### Required Data Files

You must obtain and place the following files in `data/raw/`:

#### 1. H-1B FOIA Petition Data
- **Files**: `TRK_13139_FY2021.csv`, `TRK_13139_FY2022.csv`, `TRK_13139_FY2023.csv`, `TRK_13139_FY2024_single_reg.csv`, `TRK_13139_FY2024_multi_reg.csv`
- **Source**: [Bloomberg H-1B Immigration Data](https://github.com/BloombergGraphics/2024-h1b-immigration-data)
- **Description**: Detailed H-1B lottery and petition data for fiscal years 2021-2024

#### 2. Labor Condition Application (LCA) Data
- **Directory**: `data/raw/LCA_Data/`
- **Files**: Quarterly LCA files for 2020-2024, annual files for 2015-2019
- **Source**: [DOL OFLC](https://www.dol.gov/agencies/eta/foreign-labor/performance)
- **Format**:
  - `LCA_Disclosure_Data_FY20XX_QX.xlsx` (2020-2024)
  - `H-1B_Disclosure_Data_FY20XX.xlsx` (2015-2019)

#### 3. ACS Microdata (IPUMS)
- **Files**: `usa_00061.xml` (DDI) and `usa_00061.dat.gz` (microdata)
- **Source**: [IPUMS USA](https://usa.ipums.org/)
- **Years**: 2021-2023 ACS
- **Required Variables**:
  - `YEAR`, `AGE`, `CITIZEN`, `INCWAGE`, `EMPSTAT`, `PERWT`
  - `EDUCD` (education code)
  - `OCCSOC` (occupation SOC code)
  - **`PUMA`** (Public Use Microdata Area) - **CRITICAL for new control configuration**
- **Sample**: Use 1% or higher sample for sufficient cell sizes

#### 4. SOC Code Definitions
- **File**: `soc_2018_definitions.xlsx`
- **Source**: [BLS SOC](https://www.bls.gov/soc/)

#### 5. Geographic Crosswalks
- **Files**:
  - `ZIP_COUNTY_122024.xlsx` - HUD ZIP to County crosswalk
  - `ZIP_CBSA_122024.xlsx` - HUD ZIP to CBSA crosswalk
  - `area_definitions_m2023.xlsx` - County to MSA crosswalk
- **Sources**:
  - [HUD USPS ZIP Code Crosswalk Files](https://www.huduser.gov/portal/datasets/usps_crosswalk.html)
  - [BLS MSA Definitions](https://www.bls.gov/oes/current/msa_def.htm)

#### 6. Occupation Code Crosswalks
- **Files**:
  - `soc_2010_to_2018_crosswalk.xlsx` - SOC 2010 to 2018 mapping
  - `DOT_to_ONET_SOC.xlsx` - DOT to SOC crosswalk
- **Source**: [BLS SOC](https://www.bls.gov/soc/)

#### 7. OFLC Wage Level Data
- **Directory**: `data/raw/OFLC_Wages_2024-25/`
- **Files**: `ALC_Export_FY2020.csv` through `ALC_Export_FY2023.csv`
- **Source**: [OFLC Performance Data](https://www.dol.gov/agencies/eta/foreign-labor/performance)

### Auto-Downloaded Data

The following data is automatically downloaded by the pipeline:
- Census ZCTA to PUMA crosswalks (2020 and 2010)
- Census PUMA relationship files

## Variable Linking and Standardization

### Key Variables Across Datasets

The pipeline carefully standardizes variables to enable linking:

| Variable | H-1B Data | ACS Data | Notes |
|----------|-----------|----------|-------|
| **YEAR** | `registration_lottery_year` | `YEAR` | FY year (H-1B) → Calendar year (ACS) |
| **AGE** | Calculated from `registration_birth_year` | `AGE` | Integer |
| **OCCSOC** | `SOC_CODE` (cleaned, no hyphens) | `OCCSOC` | 6-digit SOC code as character |
| **EDUCD** | `petition_beneficiary_edu_code` (mapped) | `EDUCD` | Integer education codes |
| **INCWAGE** | `petition_annual_pay_clean` | `INCWAGE` | Annual wages in dollars |
| **PUMA** | `PUMA_2010` (from geocoding) | `PUMA` | 7-digit code (state FIPS + PUMA) |

### Important Data Type Conversions

1. **SOC Codes**: Converted to character type and stripped of hyphens for consistent matching
   - H-1B: `"15-1252"` → `"151252"`
   - ACS: Already numeric, converted to character

2. **Education Codes**: H-1B petition codes mapped to ACS EDUCD values
   ```r
   "A" (< HS)     → 1
   "B" (HS)       → 63
   "C" (Some col) → 65
   "D" (Associate)→ 71
   "E" (Bachelor) → 81
   "F" (Master)   → 101
   "G" (Prof deg) → 114
   "H/I" (PhD)    → 115/116
   ```

3. **PUMA Codes**:
   - H-1B addresses geocoded to 2020 PUMAs, then crosswalked to 2010 PUMAs
   - Use 2010 PUMAs for matching with 2021-2023 ACS (which uses 2010 PUMA boundaries)
   - Format: 7-digit string (2-digit state FIPS + 5-digit PUMA code)

4. **Age Groups**: Created consistently across both datasets
   - Bins: [20,25), [25,30), [30,35), [35,40), [40,45), [45,50), [50,55), [55,60), [60,65)

### Control Configurations

The analysis supports five control configurations:

1. **age_only**: `YEAR` + `age_grp`
2. **age_education**: `YEAR` + `EDUCD` + `age_grp`
3. **age_occupation**: `YEAR` + `OCCSOC` + `age_grp`
4. **full**: `YEAR` + `EDUCD` + `OCCSOC` + `age_grp`
5. **age_occ_ed_puma** (NEW): `YEAR` + `EDUCD` + `OCCSOC` + `age_grp` + `PUMA`

## Installation and Setup

### 1. System Requirements

- **R**: Version 4.0.0 or higher
- **RStudio**: Recommended for interactive use
- **Memory**: At least 16GB RAM recommended (ACS data is large)
- **Disk Space**: At least 10GB for data files

### 2. R Package Dependencies

The pipeline will attempt to install missing packages automatically. Required packages:

```r
# Data manipulation
install.packages(c("dplyr", "tidyr", "readr", "purrr", "stringr"))

# File I/O
install.packages(c("readxl", "ipumsr"))

# Geocoding and spatial data
install.packages(c("tidygeocoder", "sf", "tidycensus"))

# String matching
install.packages("fuzzyjoin")

# Visualization and formatting
install.packages(c("ggplot2", "scales", "knitr"))

# Statistics
install.packages("matrixStats")
```

### 3. Clone or Download Repository

```bash
git clone https://github.com/yourusername/h1b_analysis_pipeline.git
cd h1b_analysis_pipeline
```

### 4. Configure Paths

Edit `config.R` to set paths appropriate for your system. By default, paths are relative to the project directory.

### 5. Obtain Data Files

Place all required data files in `data/raw/` as described in the Data Requirements section above.

## Usage

### Running the Complete Pipeline

The easiest way to run the analysis is using the main pipeline script:

```r
# In R or RStudio, from the project directory:
source("run_pipeline.R")
```

This will:
1. Check for required data files
2. Run all three steps in sequence
3. Generate output files and visualizations

### Running Individual Steps

You can also run steps independently:

```r
# Step 1: Data Cleaning
source("scripts/01_data_cleaning.R")

# Step 2: Geocoding
source("scripts/02_geocode_to_pumas.R")

# Step 3: Wage Premium Analysis
source("scripts/03_wage_premium_analysis.R")
```

### Customizing Pipeline Execution

Edit `run_pipeline.R` to skip certain steps:

```r
run_step1_cleaning <- FALSE   # Skip data cleaning
run_step2_geocoding <- TRUE   # Run geocoding
run_step3_analysis <- TRUE    # Run analysis
```

## Outputs

### Data Outputs

- `data/intermediate/h1b_fy21_24_cleaned.csv`: Cleaned H-1B data with wage levels
- `data/processed/h1b_fy21_24_with_pumas.csv`: H-1B data with PUMA codes added

### Analysis Outputs

Outputs are saved to `output/figures/` and `output/tables/`:

- Wage premium by age group (all control configurations)
- Comparisons by H-1B dependency status
- Comparisons by DOL wage level
- Comparisons by prior visa status
- Top H-1B occupations
- Summary statistics tables

## Troubleshooting

### Common Issues

**Issue**: "PUMA variable not found in ACS data"
- **Solution**: Re-download your ACS extract from IPUMS and include the PUMA variable

**Issue**: "Missing required files"
- **Solution**: Ensure all data files listed in Data Requirements are in `data/raw/`

**Issue**: Script fails during geocoding
- **Solution**: The Census API may be temporarily unavailable. The script caches downloads, so you can re-run safely.

**Issue**: Low merge rates for PUMA controls
- **Solution**: Check that:
  - H-1B data has valid ZIP codes
  - PUMA geocoding completed successfully
  - ACS data includes PUMA variable
  - PUMA codes are character type in both datasets

### Python Scripts (DOT Matching)

The data cleaning script calls Python scripts for occupation code matching:
- `dot_soc_xwalk_match.py`
- `dot_soc_matching.py`

These should be placed in `data/intermediate/dot_matching/`. Contact the original authors (Jiaxin He, Sarah Eckhardt) for these files.

## Authors and Citation

**Pipeline Integration**: Connor O'Brien (2026)

**Original Scripts**:
- Data Cleaning: Jiaxin He (jiaxin@eig.org), Sarah Eckhardt (sarah@eig.org)
- Wage Premium Analysis: [Original author]
- Geocoding: [Original author]

**Data Sources**:
- H-1B FOIA Data: Bloomberg Graphics
- ACS Microdata: IPUMS USA
- Geographic Crosswalks: Census Bureau, HUD, BLS

If you use this pipeline in your research, please cite:
```
O'Brien, C. (2026). H-1B Wage Premium Analysis Pipeline. GitHub repository.
```

## License

[Specify your license here]

## Contact

For questions or issues:
- Open an issue on GitHub
- Contact: [your email]

## Changelog

### Version 1.0 (2026-01-23)
- Initial integrated pipeline
- Added PUMA control configuration
- Standardized paths and data linking
- Created comprehensive documentation
