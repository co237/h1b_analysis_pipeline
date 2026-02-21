# Data Setup Guide

This guide tells you exactly what files to place where before running the pipeline.

## Quick Checklist

Before running the pipeline, you need these files in `data/raw/`:

- [ ] 5 H-1B FOIA petition CSV files
- [ ] LCA data files (in `LCA_Data/` subfolder)
- [ ] 2 ACS IPUMS files (DDI + data)
- [ ] SOC definitions Excel file
- [ ] 4 geographic crosswalk files
- [ ] 2 occupation crosswalk files
- [ ] OFLC wage level files (in `OFLC_Wages_2024-25/` subfolder)

## Detailed File Placement

### 1. H-1B FOIA Petition Data (5 files)

**Location**: `data/raw/`

**Files to download**:
```
TRK_13139_FY2021.csv
TRK_13139_FY2022.csv
TRK_13139_FY2023.csv
TRK_13139_FY2024_single_reg.csv
TRK_13139_FY2024_multi_reg.csv
```

**Where to get them**:
- Source: https://github.com/BloombergGraphics/2024-h1b-immigration-data
- Download the CSV files from the GitHub repository
- Place directly in `data/raw/` (not in a subfolder)

**What they look like**:
```
Documents/GitHub/h1b_analysis_pipeline/
└── data/
    └── raw/
        ├── TRK_13139_FY2021.csv          ← Here
        ├── TRK_13139_FY2022.csv          ← Here
        ├── TRK_13139_FY2023.csv          ← Here
        ├── TRK_13139_FY2024_single_reg.csv ← Here
        └── TRK_13139_FY2024_multi_reg.csv  ← Here
```

---

### 2. Labor Condition Application (LCA) Data

**Location**: `data/raw/LCA_Data/` (create this subfolder)

**Files to download**:

**Quarterly files (2020-2024)**:
```
LCA_Disclosure_Data_FY2020_Q1.xlsx
LCA_Disclosure_Data_FY2020_Q2.xlsx
LCA_Disclosure_Data_FY2020_Q3.xlsx
LCA_Disclosure_Data_FY2020_Q4.xlsx
LCA_Disclosure_Data_FY2021_Q1.xlsx
... (continue for Q2, Q3, Q4 for each year 2020-2024)
LCA_Disclosure_Data_FY2024_Q1.xlsx
LCA_Disclosure_Data_FY2024_Q2.xlsx
LCA_Disclosure_Data_FY2024_Q3.xlsx
LCA_Disclosure_Data_FY2024_Q4.xlsx
```

**Annual files (2015-2019)**:
```
H-1B_Disclosure_Data_FY2015.xlsx
H-1B_Disclosure_Data_FY2016.xlsx
H-1B_Disclosure_Data_FY2017.xlsx
H-1B_Disclosure_Data_FY2018.xlsx
H-1B_Disclosure_Data_FY2019.xlsx
```

**Where to get them**:
- Source: https://www.dol.gov/agencies/eta/foreign-labor/performance
- Look for "LCA Disclosure Data" section
- Download all quarterly files from 2020-2024
- Download all annual files from 2015-2019

**Folder structure**:
```
Documents/GitHub/h1b_analysis_pipeline/
└── data/
    └── raw/
        └── LCA_Data/                           ← Create this folder
            ├── LCA_Disclosure_Data_FY2020_Q1.xlsx
            ├── LCA_Disclosure_Data_FY2020_Q2.xlsx
            ├── ... (all other quarterly files)
            ├── H-1B_Disclosure_Data_FY2015.xlsx
            ├── H-1B_Disclosure_Data_FY2016.xlsx
            └── ... (all other annual files)
```

---

### 3. ACS Microdata from IPUMS (2 files)

**Location**: `data/raw/`

**Files you'll have**:
```
usa_00061.xml          (DDI metadata file)
usa_00061.dat.gz       (microdata file)
```
*Note: Your extract number (00061) may be different*

**Where to get them**:
1. Go to https://usa.ipums.org/
2. Register for an account if you don't have one
3. Create a new extract with these specifications:
   - **Samples**: 2021 ACS, 2022 ACS, 2023 ACS (use 1% or higher)
   - **Variables** (CRITICAL - select ALL of these):
     - YEAR
     - AGE
     - CITIZEN
     - INCWAGE
     - EMPSTAT
     - PERWT
     - EDUCD (education)
     - OCCSOC (occupation SOC code)
     - **PUMA** ← VERY IMPORTANT! Don't forget this!
4. Submit extract and download when ready
5. You'll get 2 files: a .xml file and a .dat.gz file

**Folder structure**:
```
Documents/GitHub/h1b_analysis_pipeline/
└── data/
    └── raw/
        ├── usa_00061.xml          ← DDI file here
        └── usa_00061.dat.gz       ← Data file here
```

**IMPORTANT**: The PUMA variable is required for the new control configuration!

---

### 4. SOC Code Definitions (1 file)

**Location**: `data/raw/`

**File**:
```
soc_2018_definitions.xlsx
```

**Where to get it**:
- Source: https://www.bls.gov/soc/
- Look for "2018 SOC Definitions"
- Download the Excel file

**Folder structure**:
```
Documents/GitHub/h1b_analysis_pipeline/
└── data/
    └── raw/
        └── soc_2018_definitions.xlsx    ← Here
```

---

### 5. Geographic Crosswalk Files (3 files)

**Location**: `data/raw/`

**Files**:
```
ZIP_COUNTY_122024.xlsx
ZIP_CBSA_122024.xlsx
area_definitions_m2023.xlsx
```

**Where to get them**:

1. **ZIP_COUNTY_122024.xlsx** and **ZIP_CBSA_122024.xlsx**:
   - Source: https://www.huduser.gov/portal/datasets/usps_crosswalk.html
   - Download "ZIP-COUNTY" and "ZIP-CBSA" crosswalk files
   - Use the December 2024 (Q4 2024) version

2. **area_definitions_m2023.xlsx**:
   - Source: https://www.bls.gov/oes/current/msa_def.htm
   - Download "Metropolitan and Nonmetropolitan Area Definitions"
   - Look for May 2023 definitions

**Folder structure**:
```
Documents/GitHub/h1b_analysis_pipeline/
└── data/
    └── raw/
        ├── ZIP_COUNTY_122024.xlsx       ← Here
        ├── ZIP_CBSA_122024.xlsx         ← Here
        └── area_definitions_m2023.xlsx  ← Here
```

---

### 6. Occupation Code Crosswalks (2 files)

**Location**: `data/raw/`

**Files**:
```
soc_2010_to_2018_crosswalk.xlsx
DOT_to_ONET_SOC.xlsx
```

**Where to get them**:
- Source: https://www.bls.gov/soc/
- Look for "2010 to 2018 SOC Crosswalk"
- Look for "DOT to O*NET-SOC Crosswalk"

**Folder structure**:
```
Documents/GitHub/h1b_analysis_pipeline/
└── data/
    └── raw/
        ├── soc_2010_to_2018_crosswalk.xlsx  ← Here
        └── DOT_to_ONET_SOC.xlsx             ← Here
```

---

### 7. OFLC Wage Level Data (4 files)

**Location**: `data/raw/OFLC_Wages_2024-25/` (create this subfolder)

**Files**:
```
ALC_Export_FY2020.csv
ALC_Export_FY2021.csv
ALC_Export_FY2022.csv
ALC_Export_FY2023.csv
```

**Where to get them**:
- Source: https://www.dol.gov/agencies/eta/foreign-labor/performance
- Look for "Prevailing Wage Determination" data
- Download the "All Countries" exports for fiscal years 2020-2023

**Folder structure**:
```
Documents/GitHub/h1b_analysis_pipeline/
└── data/
    └── raw/
        └── OFLC_Wages_2024-25/              ← Create this folder
            ├── ALC_Export_FY2020.csv
            ├── ALC_Export_FY2021.csv
            ├── ALC_Export_FY2022.csv
            └── ALC_Export_FY2023.csv
```

---

## Quick Setup Commands

Create all necessary directories:

```bash
cd ~/Documents/GitHub/h1b_analysis_pipeline/data/raw
mkdir -p LCA_Data
mkdir -p OFLC_Wages_2024-25
```

## Final Folder Structure

When you're done, `data/raw/` should look like this:

```
data/raw/
├── TRK_13139_FY2021.csv
├── TRK_13139_FY2022.csv
├── TRK_13139_FY2023.csv
├── TRK_13139_FY2024_single_reg.csv
├── TRK_13139_FY2024_multi_reg.csv
├── usa_

00061.xml
├── usa_00061.dat.gz
├── soc_2018_definitions.xlsx
├── ZIP_COUNTY_122024.xlsx
├── ZIP_CBSA_122024.xlsx
├── area_definitions_m2023.xlsx
├── soc_2010_to_2018_crosswalk.xlsx
├── DOT_to_ONET_SOC.xlsx
├── LCA_Data/
│   ├── LCA_Disclosure_Data_FY2020_Q1.xlsx
│   ├── LCA_Disclosure_Data_FY2020_Q2.xlsx
│   ├── ... (all quarterly 2020-2024)
│   ├── H-1B_Disclosure_Data_FY2015.xlsx
│   └── ... (all annual 2015-2019)
└── OFLC_Wages_2024-25/
    ├── ALC_Export_FY2020.csv
    ├── ALC_Export_FY2021.csv
    ├── ALC_Export_FY2022.csv
    └── ALC_Export_FY2023.csv
```

## Files That Are Downloaded Automatically

You do NOT need to manually download these (the scripts will get them):
- Census ZCTA to PUMA crosswalks (2020 and 2010 vintages)
- These will be cached in `data/raw/census_crosswalks/` automatically

## Verification

Before running the pipeline, you can check if you have everything:

```r
# In R, from the project directory:
source("config.R")
check_required_files()  # This will tell you what's missing
```

## Getting Help

If you're having trouble finding any of these files:
1. Check the README.md for direct links
2. The URLs in this guide should take you to the right place
3. Some data sources may require free registration (like IPUMS)

## Most Common Missing Items

People usually forget:
1. ✗ PUMA variable in ACS extract (most critical!)
2. ✗ Creating the `LCA_Data/` subfolder
3. ✗ Creating the `OFLC_Wages_2024-25/` subfolder
4. ✗ Downloading ALL quarterly LCA files (2020-2024)

Don't forget these! ☝️
