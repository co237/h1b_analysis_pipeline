# Changes and Improvements - February 2026

## Summary

This document summarizes the major fixes, improvements, and new features added to the H-1B analysis pipeline.

---

## 🔧 Critical Bug Fix: Year Matching Correction

### Problem Identified
Several analysis sections were incorrectly using the **fiscal year** (FY) when comparing H-1B wages to ACS native wages, instead of using the **employment year**. This created a one-year mismatch.

### Example of the Problem
- FY 2022 H-1Bs (who worked in employment year **2021**) were being compared to ACS **2022** natives ❌
- This was happening in:
  - Wage distribution charts
  - Level III+ analysis
  - Top employers analysis
  - Industry/NAICS analysis

### Solution Applied
Fixed all instances to use `employment_year = registration_lottery_year - 1`:
- FY 2022 → Employment year 2021 → ACS 2021 ✅
- FY 2023 → Employment year 2022 → ACS 2022 ✅
- FY 2024 → Employment year 2023 → ACS 2023 ✅

### Files Modified
- `scripts/03_wage_premium_analysis.R` (5 separate fixes at lines 1031, 1385, 1551, 1704, 1964)

### Impact
All wage premium calculations now correctly compare H-1B workers to native-born workers in the **same calendar year** they were employed, ensuring accurate year-over-year comparisons.

---

## 🆕 New Feature: Comprehensive Export File

### What Was Added
New script `scripts/04_export_h1b_comparisons.R` that creates a comprehensive CSV file with:
- All 273,545 H-1B workers from FY 2022-2024
- Native wage benchmarks for ALL 5 control configurations
- Calculated wage premiums for each control group
- Clearly labeled columns for easy analysis

### Output File
**Location**: `output/tables/h1b_with_native_comparisons_fy2022_2024.csv`
**Size**: ~45 MB
**Records**: 273,545

### Columns Included
**Identifiers:**
- `applicant_id`
- `registration_lottery_year` (FY 2022, 2023, or 2024)
- `employment_year` (2021, 2022, or 2023)

**H-1B Worker Characteristics:**
- `h1b_wage`: Annual wage
- `age`, `age_group`
- `education_code`
- `occupation_soc`, `occupation_title`
- `puma_code`
- `employer_name`
- `h1b_dependent` (Y/N)
- `wage_level` (I, II, III, IV)
- `prior_visa`

**Native Wage Benchmarks (median wage of comparable natives):**
- `native_wage_age_only`
- `native_wage_age_education`
- `native_wage_age_occupation`
- `native_wage_full`
- `native_wage_puma`

**Wage Premiums (H-1B wage - Native wage):**
- `premium_age_only`
- `premium_age_education`
- `premium_age_occupation`
- `premium_full`
- `premium_puma`

### Merge Rates
- age_only: 100.0% (all H-1Bs matched)
- age_education: 76.5%
- age_occupation: 82.4%
- full: 63.4%
- puma: 17.5%

---

## 📁 File Organization for GitHub + Google Drive

### New Documentation
Created `DATA_GOOGLE_DRIVE.md` with comprehensive instructions for:
- Which files go on GitHub vs. Google Drive
- Setting up symbolic links for local development
- Sharing data with collaborators
- File size guidelines

### Updated .gitignore
Enhanced `.gitignore` to:
- Exclude all large data files from git
- Keep README files in data directories
- Document which files go where

### File Size Guidelines
- **GitHub**: Files < 100 MB (code, scripts, docs, small reference files)
- **Google Drive**: Files > 100 MB (raw data, intermediate outputs, large tables)

### Google Drive Folder Structure
```
h1b_analysis_pipeline_data/
├── raw/ (~1.5 GB)
│   ├── FOIA_Data/
│   ├── LCA_Data/
│   ├── usa_00068.dat.gz (155 MB)
│   └── Other Data/
├── intermediate/ (~670 MB)
│   ├── h1b_fy21_24_cleaned.csv (334 MB)
│   ├── step1_lca_processed.RData (98 MB)
│   └── step2_foia_processed.RData (77 MB)
├── processed/ (~350 MB)
│   └── h1b_fy21_24_with_pumas.csv (350 MB)
└── output/
    ├── figures/ (30+ PNG charts)
    └── tables/
        └── h1b_with_native_comparisons_fy2022_2024.csv (45 MB)
```

---

## 📊 Pipeline Updates

### New 6-Step Pipeline
Updated `run_pipeline_simple.R` to include:
1. Process LCA data
2. Process FOIA data
3. Merge and clean
4. Geocode to PUMAs
5. **Wage premium analysis** (with year fixes)
6. **Export comparisons file** (NEW)

### Checkpoint Recovery
Pipeline automatically skips completed steps, allowing for crash recovery and incremental runs.

---

## 📖 Documentation Updates

### README.md
- Added "Recent Updates" section documenting the year fix
- Updated repository structure to show new files
- Updated usage instructions for 6-step pipeline
- Added detailed explanation of export file structure
- Fixed ACS filename reference (usa_00068 instead of usa_00061)

### New Documentation Files
1. **DATA_GOOGLE_DRIVE.md**: Complete guide for organizing large files
2. **CHANGES_FEB_2026.md**: This file - comprehensive change log

### Updated Files
- `.gitignore`: Enhanced to handle GitHub + Google Drive workflow
- `config.R`: Already had correct paths, no changes needed

---

## ✅ Testing and Validation

### Pipeline Run Results
Successfully ran the complete pipeline with the fixes:

**Data Processing:**
- H-1B records loaded: 373,117
- H-1B records after cleaning: 273,545
- Native-born ACS records: 3,332,843
- Final panel size: 3,606,388

**Year Distribution (confirmed correct):**
- Employment year 2021: 89,636 H-1Bs (from FY 2022)
- Employment year 2022: 93,084 H-1Bs (from FY 2023)
- Employment year 2023: 90,825 H-1Bs (from FY 2024)

**PUMA Matching:**
- 2010 PUMA vintage: 89,636 (for employment year 2021 / ACS 2021)
- 2020 PUMA vintage: 183,909 (for employment years 2022-23 / ACS 2022-23)
- PUMA overlap by year: ~80% (excellent match rate)

**Outputs Generated:**
- 30+ charts saved to `output/figures/`
- Summary tables in `output/tables/`
- Export file: 273,545 records, 45.3 MB

---

## 📝 Next Steps for Publication

### Before Pushing to GitHub:
1. ✅ Remove large data files from repository (already in .gitignore)
2. ✅ Keep all code, scripts, and documentation
3. Create Google Drive folder and upload large data files
4. Add Google Drive sharing link to README.md
5. Create a sample/subset of data for testing (optional)

### For Collaborators:
1. Clone GitHub repository (code only)
2. Access Google Drive folder for data files
3. Follow setup instructions in DATA_GOOGLE_DRIVE.md
4. Run pipeline with `source("run_pipeline_simple.R")`

### Optional Enhancements:
- Create a Zenodo/OSF archive for long-term data preservation
- Add DOI for data citation
- Create reproducibility guide with package versions
- Add unit tests for key functions

---

## 🎯 Summary of Improvements

| Area | Improvement | Impact |
|------|-------------|--------|
| **Year Matching** | Fixed 5 instances of year mismatch | Ensures accurate year-over-year comparisons |
| **Data Export** | New comprehensive export file | Easy access to all H-1B + native comparisons |
| **Documentation** | Enhanced README + new guides | Clearer setup and usage instructions |
| **File Organization** | GitHub + Google Drive structure | Enables collaboration without git bloat |
| **Pipeline** | 6-step pipeline with checkpoints | More robust execution with recovery |

---

## 📧 Contact

For questions about these changes:
- Review this document
- Check DATA_GOOGLE_DRIVE.md for file organization
- See README.md for usage instructions
- Review code comments in modified scripts

---

**Document Version**: 1.0
**Date**: February 20, 2026
**Author**: Pipeline maintenance and improvements
