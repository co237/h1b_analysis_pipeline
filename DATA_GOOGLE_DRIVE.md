# Large Data Files - Google Drive Organization

This document explains where the large data files are stored and how to access them.

## ✅ Google Drive Folder Created!

**Location**: `Google Drive > My Drive > h1b_analysis_pipeline_data`

**Direct Path** (for Connor):
`~/Library/CloudStorage/GoogleDrive-connor@ifp.org/My Drive/h1b_analysis_pipeline_data/`

**Total Size**: ~8.2 GB

## File Size Guidelines

- **GitHub**: Files < 100 MB (code, scripts, documentation, small reference files)
- **Google Drive**: Files > 100 MB (raw data, intermediate outputs, large analysis files)

## Google Drive Folder Structure

The shared Google Drive folder has been created with the following structure:

```
h1b_analysis_pipeline_data/
├── raw/
│   ├── FOIA_Data/
│   │   ├── TRK_13139_FY2021.csv (~50 MB)
│   │   ├── TRK_13139_FY2022.csv (~80 MB)
│   │   ├── TRK_13139_FY2023.csv (~90 MB)
│   │   ├── TRK_13139_FY2024_single_reg.csv (~40 MB)
│   │   └── TRK_13139_FY2024_multi_reg.csv (~5 MB)
│   ├── LCA_Data/
│   │   └── [Quarterly LCA files 2020-2024, Annual files 2015-2019]
│   ├── usa_00068.xml (~85 KB - can go in GitHub)
│   ├── usa_00068.dat.gz (~155 MB - must be in Google Drive)
│   └── Other Data/
│       ├── OFLC_Wages_2024-25/
│       ├── ZIP_COUNTY_122024.xlsx
│       ├── ZIP_CBSA_122024.xlsx
│       ├── area_definitions_m2023.xlsx
│       ├── soc_2018_definitions.xlsx
│       └── soc_2010_to_2018_crosswalk.xlsx
│
├── intermediate/
│   ├── step1_lca_processed.RData (~98 MB)
│   ├── step2_foia_processed.RData (~77 MB)
│   ├── lca_2020_2024.RData (~47 MB)
│   ├── lca_2015_2024.RData (~101 MB)
│   └── h1b_fy21_24_cleaned.csv (~334 MB)
│
├── processed/
│   └── h1b_fy21_24_with_pumas.csv (~350 MB)
│
└── output/
    ├── figures/
    │   └── [All PNG charts - ~50-100 KB each]
    └── tables/
        ├── h1b_with_native_comparisons_fy2022_2024.csv (~60 MB)
        └── [Other summary tables]
```

## Setup Instructions for Collaborators

### 1. Clone the GitHub Repository

```bash
git clone https://github.com/yourusername/h1b_analysis_pipeline.git
cd h1b_analysis_pipeline
```

### 2. Get Access to Google Drive Folder

**Contact Connor O'Brien (connor@ifp.org) for access to:**
`h1b_analysis_pipeline_data` folder in Google Drive

### 3. Download Data from Google Drive

**Option A: Manual Download**
1. Access the shared Google Drive folder (link provided after access granted)
2. Download the folders: `raw/`, `intermediate/`, `processed/`, `output/`
3. Place them in your local `h1b_analysis_pipeline/data/` directory

**Option B: Google Drive Desktop**
1. Install Google Drive for Desktop
2. Sync the shared folder
3. Create symbolic links to your project:

```bash
# On Mac/Linux:
cd h1b_analysis_pipeline
ln -s "/path/to/GoogleDrive/h1b_analysis_pipeline_data/raw" data/raw
ln -s "/path/to/GoogleDrive/h1b_analysis_pipeline_data/intermediate" data/intermediate
ln -s "/path/to/GoogleDrive/h1b_analysis_pipeline_data/processed" data/processed

# On Windows (run as Administrator):
cd h1b_analysis_pipeline
mklink /D data\raw "C:\path\to\GoogleDrive\h1b_analysis_pipeline_data\raw"
mklink /D data\intermediate "C:\path\to\GoogleDrive\h1b_analysis_pipeline_data\intermediate"
mklink /D data\processed "C:\path\to\GoogleDrive\h1b_analysis_pipeline_data\processed"
```

### 3. Verify Data Files

```r
# In R:
source("config.R")

# Check for required files
file.exists(acs_ddi_file)  # Should be TRUE
file.exists(file.path(data_processed, "h1b_fy21_24_with_pumas.csv"))  # Should be TRUE
```

## Data Sources and Download Links

### Required Data Files (must download manually)

1. **H-1B FOIA Data** (Bloomberg)
   - Source: https://github.com/BloombergGraphics/2024-h1b-immigration-data
   - Files: `TRK_13139_FY2021.csv` through `TRK_13139_FY2024*.csv`
   - Total size: ~265 MB

2. **LCA Data** (Department of Labor)
   - Source: https://www.dol.gov/agencies/eta/foreign-labor/performance
   - Files: Quarterly LCA files 2020-2024, Annual files 2015-2019
   - Total size: ~500 MB

3. **ACS IPUMS Microdata**
   - Source: https://usa.ipums.org/
   - Extract: Years 2021-2023, 1% sample
   - Variables: YEAR, AGE, CITIZEN, INCWAGE, EMPSTAT, PERWT, EDUCD, OCCSOC, PUMA, STATEFIP
   - Files: `usa_00068.xml` and `usa_00068.dat.gz`
   - Total size: ~155 MB

4. **Geographic Crosswalks** (various)
   - HUD ZIP-County: https://www.huduser.gov/portal/datasets/usps_crosswalk.html
   - BLS MSA Definitions: https://www.bls.gov/oes/current/msa_def.htm
   - SOC Crosswalks: https://www.bls.gov/soc/

5. **OFLC Wage Levels**
   - Source: https://www.dol.gov/agencies/eta/foreign-labor/performance
   - Files: `ALC_Export_FY2020.csv` through `ALC_Export_FY2023.csv`

## File Sharing Permissions

- **Google Drive Folder**: Set to "Anyone with the link can view" OR "Specific people with edit access"
- **Recommended**: Use organization/university Google Workspace for unlimited storage
- **Alternative**: For public release, consider Zenodo, OSF, or Harvard Dataverse for data archiving

## GitHub Repository Contents

The GitHub repository contains:
- ✅ All R scripts and analysis code
- ✅ Configuration files
- ✅ Documentation (README, guides, etc.)
- ✅ Small reference files (< 1 MB)
- ✅ Sample output charts (small PNGs)
- ❌ Large data files (see Google Drive structure above)
- ❌ Intermediate processing files
- ❌ Large output tables

## Version Control

- **Data files**: Not version controlled (use Google Drive file versions)
- **Code**: Fully version controlled in Git
- **Outputs**: Can be regenerated from data + code, store latest in Google Drive

## Questions?

If you have trouble accessing or setting up the data files, please:
1. Check this documentation
2. Verify your Google Drive permissions
3. Contact the repository maintainer
