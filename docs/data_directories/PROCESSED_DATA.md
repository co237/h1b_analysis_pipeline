# Processed Data Files

This folder (`data/processed/`) contains final processed datasets ready for analysis. NOT tracked in Git due to size.

**Note:** This directory is a symbolic link to Google Drive for easy sharing and large file storage.

## Contents (~350 MB)

### Final Datasets

#### H-1B Petition Data
- **h1b_with_percentiles_and_native_comps.csv** (350 MB)
  - Output of step 3 (03 interpolate wage percentiles.R)
  - H-1B petition data with percentile assignments
  - Used as input for Mincer wage calculation (Script 04, 05)

- **h1b_with_mincer_wages.csv**
  - Output of step 5 (05 Apply new PWs to H1B petitions.R)
  - H-1B petitions tagged with Experience Benchmarking prevailing wages
  - Contains pw_p50, pw_p62, pw_p75, pw_p90 for each petition

#### Mincer Model Outputs
- **mincer_edu_exp_ratios.rds** / **.csv**
  - Output of Script 04 (Calculate new prevailing wages.R)
  - Education-experience adjustment ratios for all occupations
  - Used by lookup function and Script 05

- **oflc_bases.rds**
  - Flattened OFLC Level 3 wages by SOC code, area, year, and wage type
  - Used by lookup function for instant wage queries

- **crosswalks.rds**
  - SOC 2018 → ACS 2018 crosswalk (FY2023+)
  - SOC 2010 → ACS 2018 crosswalk (FY2021-2022)
  - Used by lookup function

## Usage
These are the final datasets produced by the pipeline:
- If you have these files and ACS data, you can run analysis without running earlier steps
- The `.rds` files are optimized for fast loading in R
- The `.csv` files provide human-readable versions where applicable
