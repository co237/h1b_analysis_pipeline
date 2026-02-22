# Processed Data Files

Final processed datasets ready for analysis. NOT tracked in Git due to size.

## Contents (~350 MB)

### Final Dataset
- **h1b_fy21_24_with_pumas.csv** (350 MB)
  - Output of step 4 (02_geocode_to_pumas.R)
  - H-1B petition data with PUMA geocoding
  - Used as input for wage premium analysis (step 5)
  - Contains:
    - All cleaned H-1B fields
    - PUMA codes (2010 and 2020 vintages)
    - Ready for merging with ACS data

## Usage
This is the primary input file for the wage premium analysis. If you have this file and the ACS data, you can run steps 5-6 of the pipeline without running steps 1-4.
