# Documentation Update Summary

**Date**: 2026-03-02

This document summarizes the comprehensive documentation overhaul following the implementation of national Mincer models with area fixed effects.

---

## Changes Made

### New Documentation

1. **README.md** (Completely Rewritten)
   - Updated to reflect national Mincer models with area FE methodology
   - Clearer quick start guide with prerequisites
   - Comprehensive pipeline step descriptions with runtimes
   - Results summary with current statistics (198,407 petitions, 72.5% match rate)
   - Troubleshooting section expanded

2. **MINCER_METHODOLOGY.md** (New)
   - Detailed technical documentation of Mincer estimation approach
   - Complete explanation of national models with area fixed effects
   - Occupation code crosswalk system documentation
   - Step-by-step data flow from raw data to final wages
   - Design decisions and rationale
   - Comprehensive FAQ section

3. **Subdirectory READMEs** (New)
   - `scripts/archived/README.md`: Documents old script versions
   - `scripts/diagnostics/README.md`: Explains diagnostic utilities
   - `scripts/crosswalks/README.md`: Documents crosswalk generation scripts

### Retained Documentation

These files were kept as they remain relevant:

- **DATA_SOURCES.md**: Data download instructions (still accurate)
- **DATA_GOOGLE_DRIVE.md**: Google Drive setup instructions (still relevant)

### Removed Documentation

These files were outdated and removed:

- ~~NATIONAL_MINCER_WITH_AREA_FE_PROPOSAL.md~~ (Implementation proposal, no longer needed)
- ~~NATIONAL_MINCER_IMPLEMENTATION_RESULTS.md~~ (Implementation notes, superseded by MINCER_METHODOLOGY.md)
- ~~TWO_STAGE_IMPLEMENTATION_RESULTS.md~~ (Historical implementation notes)
- ~~SOC_CROSSWALK_ANALYSIS.md~~ (Historical analysis)
- ~~CROSSWALK_COMPARISON.md~~ (Historical comparison)
- ~~MINCER_WAGE_CALCULATION_EXPLAINED.md~~ (Old methodology explanation, superseded by MINCER_METHODOLOGY.md)

### Scripts Organization

**Core Pipeline Scripts** (remain in `scripts/`):
- `01_data_cleaning.R`
- `02_geocode_to_pumas.R`
- `03 interpolate wage percentiles.R`
- `04 Calculate new prevailing wages.R` (Updated with national models)
- `05 Apply new PWs to H1B petitions.R` (Updated to use ratios)
- `06 nprm_simulation.R` (Updated with percentile-based logic)

**Organized Supporting Scripts**:
- `scripts/archived/`: Old script versions (OLD Calculate new wage levels.R, OLD mincer_fit.R)
- `scripts/diagnostics/`: Diagnostic utilities (DIAGNOSTIC_*.R, VERIFY_*.R)
- `scripts/crosswalks/`: Crosswalk generation scripts (create_*.R)

---

## Current Project Structure

```
h1b_analysis_pipeline/
├── README.md                       # Main documentation (UPDATED)
├── MINCER_METHODOLOGY.md           # Technical methodology (NEW)
├── DATA_SOURCES.md                 # Data sources guide
├── DATA_GOOGLE_DRIVE.md            # Google Drive setup
├── DOCUMENTATION_UPDATE.md         # This file
├── config.R                        # Configuration
├── run_all.R                       # Master script
│
├── scripts/                        # Main pipeline scripts
│   ├── 01_data_cleaning.R
│   ├── 02_geocode_to_pumas.R
│   ├── 03 interpolate wage percentiles.R
│   ├── 04 Calculate new prevailing wages.R
│   ├── 05 Apply new PWs to H1B petitions.R
│   ├── 06 nprm_simulation.R
│   │
│   ├── archived/                   # Old versions (NEW)
│   │   ├── README.md
│   │   ├── OLD Calculate new wage levels.R
│   │   └── OLD mincer_fit.R
│   │
│   ├── diagnostics/                # Diagnostic utilities (NEW)
│   │   ├── README.md
│   │   ├── DIAGNOSTIC_missing_wages.R
│   │   ├── DIAGNOSTIC_soc_oflc_match.R
│   │   └── VERIFY_soc_crosswalk_fix.R
│   │
│   └── crosswalks/                 # Crosswalk generation (NEW)
│       ├── README.md
│       ├── create_fy2021_to_acs_crosswalk.R
│       ├── create_oflc_acs_crosswalk_fy2021.R
│       ├── create_oflc_acs_crosswalk.R
│       └── create_soc2010_to_soc2018_crosswalk.R
│
├── data/
│   ├── raw/                        # Source data
│   ├── intermediate/               # Intermediate outputs
│   └── processed/                  # Final datasets
│       ├── mincer_edu_exp_ratios.csv (NEW - 119,638 ratios)
│       └── h1b_with_mincer_wages.csv (UPDATED)
│
└── output/
    ├── figures/                    # Charts
    └── tables/                     # Summary tables
```

---

## Key Methodology Changes Documented

### 1. National Mincer Models with Area Fixed Effects

**Old Approach:**
- Separate Mincer models for each occupation-area combination
- Required ≥100 observations per occupation per metro
- Lower coverage due to data constraints

**New Approach:**
- ONE national model per occupation with area fixed effects
- Only need ≥100 observations nationally
- Place-invariant education/experience premiums
- 72.5% match rate (198,407 / 273,546 petitions)

### 2. Education-Experience Ratios

**Old:** Coefficients varied by area
**New:** Ratios stored by (occupation, education, experience), not by area

**Calculation:**
1. Fit national model with area FE
2. Predict wages across all areas
3. Weight by PERWT (ACS person weights)
4. Calculate weighted average → compare to national median → store ratio

**Output:** 119,638 ratios for 377 occupations

### 3. Wage Application

**Formula:** `wage = ratio[occupation, education, experience] × OFLC_Level3[occupation, area]`

**Two-Stage Geographic Fallback:**
- Ratios: National (place-invariant)
- OFLC anchor: MSA-level → fall back to national if unavailable

### 4. NPRM Simulation Logic (Script 06)

**Updated to use percentile-based qualification:**
1. Use `petition_percentile_combined` to determine who qualifies
2. If `petition_percentile_combined >= threshold` → qualifies
3. Among those who qualify, check if `petition_wage < pw_p50` → underpaid

**No interpolation of Mincer wages** (previous incorrect approach removed)

---

## Documentation Quality Improvements

### Accessibility for New Users

- Clear quick start guide with prerequisites and installation steps
- Step-by-step pipeline explanations with expected runtimes
- Comprehensive troubleshooting section
- Links to data sources with direct URLs

### Technical Depth

- Complete explanation of national Mincer models with area FE
- Detailed crosswalk system documentation (two-stage for FY2021-2022)
- Full data flow from raw data to final wages
- Design decisions documented with rationale

### Organization

- Separated high-level overview (README.md) from technical details (MINCER_METHODOLOGY.md)
- Organized supporting scripts into subdirectories with explanatory READMEs
- Removed outdated historical documentation

---

## Current Pipeline Statistics

- **Total petitions:** 273,546 (FY 2022-2024)
- **Successful wage matching:** 198,407 (72.5%)
- **Occupations modeled:** 377
- **Education-experience ratios:** 119,638
- **Model fallbacks:** 0 (all occupations fit at 6-digit level)

### NPRM Simulation Results
Using thresholds: Level I ≥ 34th, Level II ≥ 52nd, Level III ≥ 70th, Level IV ≥ 88th percentile

- **Petitions that qualify:** 23.8% (47,289 / 198,407)
- **Among qualified, underpaid vs Mincer median:** 36.9% (17,445 / 47,289)

---

## For New Project Contributors

1. **Start here:** Read README.md for pipeline overview
2. **Understand methodology:** Read MINCER_METHODOLOGY.md for technical details
3. **Get data:** Follow DATA_SOURCES.md to obtain required files
4. **Run pipeline:** Execute `source("run_all.R")` or run scripts individually
5. **Troubleshoot:** Check README.md troubleshooting section and MINCER_METHODOLOGY.md FAQ

---

## Contact

For questions about documentation or methodology:
- Connor O'Brien (connor@ifp.org)
- GitHub Issues: [Open an issue](https://github.com/yourusername/h1b_analysis_pipeline/issues)

---

**Documentation Authors:** Institute for Progress (2026)

**Last Updated:** 2026-03-02
