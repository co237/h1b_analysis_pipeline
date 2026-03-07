# Raw Data Files

This folder (`data/raw/`) contains original source data files required for the H-1B analysis pipeline.

**Note:** This directory is a symbolic link to Google Drive for easy sharing and large file storage.

## Contents (~7.1 GB)

### H-1B FOIA Data (`FOIA Data/`)
- Source: Bloomberg H-1B Immigration Data
- Files: TRK_13139_FY2021.csv through FY2024 files
- URL: https://github.com/BloombergGraphics/2024-h1b-immigration-data

### Labor Condition Applications (`LCA_Data/`)
- Source: Department of Labor OFLC
- Files: Quarterly files (2020-2024), Annual files (2015-2019)
- URL: https://www.dol.gov/agencies/eta/foreign-labor/performance

### ACS Microdata
- **usa_00068.dat.gz** (155 MB): IPUMS USA microdata extract
- **usa_00068.xml** (85 KB): Data dictionary (DDI)
- Source: IPUMS USA
- Years: 2021-2023 ACS
- Variables: YEAR, AGE, CITIZEN, INCWAGE, EMPSTAT, PERWT, EDUCD, OCCSOC, PUMA, STATEFIP
- URL: https://usa.ipums.org/

### Reference Files (`Other Data/`)
- **OFLC_Wages_2024-25/**: Prevailing wage levels by occupation and area
- Geographic crosswalks: ZIP-County, ZIP-CBSA, County-MSA
- SOC code definitions and crosswalks
- DOT to O*NET mappings

## Notes
- These files are NOT tracked in Git due to size
- The `data/raw/` directory is a symlink to Google Drive
- See main README.md and DATA_SOURCES.md for detailed data requirements
