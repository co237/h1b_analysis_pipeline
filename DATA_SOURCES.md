# Data Sources and Download Instructions

This document provides detailed instructions for obtaining all required data files for the DOL NPRM H-1B wage analysis pipeline.

## Quick Start

**Option 1: Use Google Drive (Recommended)**
- Contact connor@ifp.org for access to the shared `h1b_analysis_pipeline_data` folder (~8.2 GB)
- All data files are pre-organized and ready to use
- See `DATA_GOOGLE_DRIVE.md` for setup instructions

**Option 2: Download Files Yourself**
- Follow the instructions below to download each required file
- This will take several hours but ensures you have the latest data

## Directory Structure

Place all downloaded files in the `data/raw/` directory according to this structure:

```
data/raw/
├── FOIA Data/
│   ├── TRK_13139_FY2021.csv
│   ├── TRK_13139_FY2022.csv
│   ├── TRK_13139_FY2023.csv
│   ├── TRK_13139_FY2024_single_reg.csv
│   └── TRK_13139_FY2024_multi_reg.csv
│
├── LCA_Data/
│   ├── LCA_Disclosure_Data_FY2020_Q1.xlsx
│   ├── LCA_Disclosure_Data_FY2020_Q2.xlsx
│   ├── ... (additional quarterly files)
│   └── H-1B_Disclosure_Data_FY2019.xlsx
│
├── OFLC_Wages_2024-25/
│   ├── ALC_Export_FY2020.csv
│   ├── ALC_Export_FY2021.csv
│   ├── ALC_Export_FY2022.csv
│   └── ALC_Export_FY2023.csv
│
├── Other Data/
│   ├── ZIP_COUNTY_122024.xlsx
│   ├── ZIP_CBSA_122024.xlsx
│   ├── area_definitions_m2023.xlsx
│   ├── soc_2010_to_2018_crosswalk.xlsx
│   └── DOT_to_ONET_SOC.xlsx
│
├── usa_00068.xml (or your IPUMS extract filename)
├── usa_00068.dat.gz (or your IPUMS extract filename)
└── soc_2018_definitions.xlsx
```

## Required Data Files

### 1. H-1B FOIA Petition Data

**What:** Detailed H-1B lottery registration and petition data for fiscal years 2021-2024

**Source:** Bloomberg Graphics H-1B Immigration Data
- **GitHub Repository:** https://github.com/BloombergGraphics/2024-h1b-immigration-data
- **Direct Download:** https://github.com/BloombergGraphics/2024-h1b-immigration-data/releases

**Files Needed:**
- `TRK_13139_FY2021.csv` (~1.2 GB)
- `TRK_13139_FY2022.csv` (~1.1 GB)
- `TRK_13139_FY2023.csv` (~1.3 GB)
- `TRK_13139_FY2024_single_reg.csv` (~1.0 GB)
- `TRK_13139_FY2024_multi_reg.csv` (~300 MB)

**Where to Place:** `data/raw/FOIA Data/`

**Instructions:**
1. Visit the GitHub releases page
2. Download all five CSV files
3. Place them in `data/raw/FOIA Data/`

---

### 2. Labor Condition Application (LCA) Data

**What:** Department of Labor LCA disclosure data containing wage and job information

**Source:** DOL Office of Foreign Labor Certification (OFLC)
- **Website:** https://www.dol.gov/agencies/eta/foreign-labor/performance
- **Direct Link:** Click "Disclosure Data" tab, then "LCA Programs (H-1B, H-1B1, E-3)"

**Files Needed:**
- **FY 2020-2024:** Quarterly files (e.g., `LCA_Disclosure_Data_FY2020_Q1.xlsx`)
- **FY 2015-2019:** Annual files (e.g., `H-1B_Disclosure_Data_FY2019.xlsx`)

**Where to Place:** `data/raw/LCA_Data/`

**Instructions:**
1. Visit the OFLC Performance Data page
2. Navigate to "Disclosure Data" → "LCA Programs"
3. Download quarterly files for FY 2020-2024
4. Download annual files for FY 2015-2019
5. Place all files in `data/raw/LCA_Data/`

**Note:** These are large Excel files (~50-200 MB each). The total size for all LCA files is ~4 GB.

---

### 3. ACS Microdata (IPUMS USA)

**What:** American Community Survey microdata for years 2021-2023 containing individual-level wage and demographic data

**Source:** IPUMS USA
- **Website:** https://usa.ipums.org/
- **Registration Required:** Free account needed

**Required Variables:**
- **Core:** `YEAR`, `AGE`, `CITIZEN`, `INCWAGE`, `EMPSTAT`, `PERWT`
- **Education:** `EDUCD`
- **Occupation:** `OCCSOC`
- **Geography:** `PUMA` (**CRITICAL** - required for geographic controls)
- **Other:** `STATEFIP`, `COUNTYFIP` (optional but helpful)

**Years:** 2021, 2022, 2023 ACS

**Sample:** 1% or higher (5% recommended for sufficient cell sizes)

**Where to Place:** `data/raw/`

**Instructions:**
1. Create a free account at https://usa.ipums.org/
2. Click "Get Data"
3. Select samples: 2021 ACS, 2022 ACS, 2023 ACS
4. Select variables (see list above)
5. **IMPORTANT:** Make sure to include `PUMA` variable
6. Select data format: Fixed-width text (.dat) with DDI codebook (.xml)
7. Submit extract request
8. Wait for email notification (can take 30 minutes to several hours)
9. Download two files:
   - DDI codebook (`.xml` file)
   - Data file (`.dat.gz` file)
10. Place both files in `data/raw/`
11. Update `config.R` line 76 with your actual filenames if different from `usa_00068.xml`

**File Size:** ~3-5 GB compressed, ~10-15 GB uncompressed

**Note:** The filename will depend on your extract number (e.g., `usa_00068.xml` or `usa_00123.xml`)

---

### 4. SOC Code Definitions

**What:** Standard Occupational Classification (SOC) 2018 code definitions

**Source:** Bureau of Labor Statistics (BLS)
- **Website:** https://www.bls.gov/soc/
- **Direct Link:** https://www.bls.gov/soc/2018/soc_2018_definitions.xlsx

**File Needed:** `soc_2018_definitions.xlsx`

**Where to Place:** `data/raw/`

**Instructions:**
1. Visit https://www.bls.gov/soc/2018/
2. Download "2018 SOC Definitions" Excel file
3. Save as `soc_2018_definitions.xlsx` in `data/raw/`

---

### 5. Geographic Crosswalks

**What:** Crosswalk files mapping ZIP codes to counties and MSAs

**Sources:**

#### a) HUD ZIP Code Crosswalk Files
- **Website:** https://www.huduser.gov/portal/datasets/usps_crosswalk.html
- **Files:**
  - `ZIP_COUNTY_122024.xlsx` - ZIP to County
  - `ZIP_CBSA_122024.xlsx` - ZIP to CBSA/MSA

**Instructions:**
1. Visit HUD USPS ZIP Code Crosswalk page
2. Download "ZIP-COUNTY" for Q4 2024 (or latest quarter)
3. Download "ZIP-CBSA" for Q4 2024 (or latest quarter)
4. Place in `data/raw/Other Data/`

#### b) BLS MSA Definitions
- **Website:** https://www.bls.gov/oes/current/msa_def.htm
- **File:** `area_definitions_m2023.xlsx`

**Instructions:**
1. Visit BLS OES MSA Definitions page
2. Download "Area Definitions" Excel file for 2023 (or latest)
3. Save as `area_definitions_m2023.xlsx` in `data/raw/Other Data/`

**Where to Place:** `data/raw/Other Data/`

---

### 6. Occupation Code Crosswalks

**What:** Crosswalks for mapping between different occupation coding systems

**Source:** Bureau of Labor Statistics

#### a) SOC 2010 to 2018 Crosswalk
- **Website:** https://www.bls.gov/soc/2018/
- **File:** `soc_2010_to_2018_crosswalk.xlsx`

**Instructions:**
1. Visit https://www.bls.gov/soc/2018/
2. Find "SOC 2010 to SOC 2018 Crosswalk"
3. Download Excel file
4. Save as `soc_2010_to_2018_crosswalk.xlsx`

#### b) DOT to SOC Crosswalk
- **Website:** https://www.bls.gov/soc/
- **File:** `DOT_to_ONET_SOC.xlsx`

**Instructions:**
1. Visit BLS SOC page
2. Find "Dictionary of Occupational Titles (DOT) to SOC" crosswalk
3. Download Excel file
4. Save as `DOT_to_ONET_SOC.xlsx`

**Where to Place:** `data/raw/Other Data/`

---

### 7. OFLC Wage Level Data (Optional)

**What:** OFLC prevailing wage determination data used for wage level analysis

**Source:** DOL OFLC Performance Data
- **Website:** https://www.dol.gov/agencies/eta/foreign-labor/performance
- **Section:** "Prevailing Wage Determinations" or "Online Wage Library"

**Files Needed:**
- `ALC_Export_FY2020.csv`
- `ALC_Export_FY2021.csv`
- `ALC_Export_FY2022.csv`
- `ALC_Export_FY2023.csv`

**Where to Place:** `data/raw/OFLC_Wages_2024-25/`

**Instructions:**
1. Visit OFLC Performance Data page
2. Navigate to "Prevailing Wage Determinations"
3. Download wage data exports for FY 2020-2023
4. Place in `data/raw/OFLC_Wages_2024-25/`

**Note:** This data is optional. The pipeline can run without it, but some wage level comparisons may be limited.

---

## Auto-Downloaded Data

The following data files are automatically downloaded by the pipeline scripts:

- **Census ZCTA to PUMA Crosswalks** (2020 and 2010)
- **Census PUMA Relationship Files**

These will be downloaded to `data/raw/census_crosswalks/` when you run the geocoding script.

---

## Verifying Your Setup

After downloading all files, run the setup script to verify everything is in place:

```r
source('setup.R')
```

This will:
- Check for all required data files
- Report which files are missing
- Guide you on next steps

---

## File Size Summary

Total data size: **~8-10 GB**

Breakdown:
- H-1B FOIA Data: ~5 GB
- LCA Data: ~4 GB
- ACS IPUMS Data: ~3-5 GB (compressed)
- Other files: ~50-100 MB

Make sure you have sufficient disk space before downloading.

---

## Troubleshooting

### IPUMS Extract Taking Too Long
IPUMS extracts can take 30 minutes to several hours depending on server load. Be patient and check your email for the notification.

### Files Have Different Names
If your files have different names (especially IPUMS files), you'll need to update `config.R` to reflect the actual filenames. Look for these variables:
- `acs_ddi_file` (line 76)
- `foia_files` (lines 62-68)

### Can't Find a Specific File
If a download link has moved:
1. Check the main website (OFLC, BLS, IPUMS)
2. Look for "Data Downloads" or "Performance Data" sections
3. Contact the data provider's help desk
4. Or request access to the Google Drive folder (connor@ifp.org)

---

## Questions?

For questions about data sources or setup:
- Open an issue on GitHub
- Contact: connor@ifp.org
