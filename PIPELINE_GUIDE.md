# H-1B Wage Premium Analysis Pipeline - Simple Guide

## Overview

This pipeline processes H-1B petition data in **7 clear steps**. Each step saves a checkpoint, so if something crashes, you don't lose your progress.

## The 7 Steps

### Step 1: Process LCA Data
**What it does:** Loads and cleans Labor Condition Application data (2015-2024)
**Input:** Excel files from `data/raw/LCA_Data/`
**Output:** `data/intermediate/step1_lca_processed.RData`
**Time:** ~5 minutes
**Memory:** ~2 GB

### Step 2: Process FOIA Data
**What it does:** Loads H-1B petition data (2021-2024) and renames variables
**Input:** CSV files from `data/raw/FOIA Data/`
**Output:** `data/intermediate/step2_foia_processed.RData`
**Time:** ~2 minutes
**Memory:** ~1 GB

### Step 3: Merge FOIA with LCA
**What it does:** Combines petition data with LCA to get SOC codes and wage levels
**Input:** Outputs from Steps 1 & 2
**Output:** `data/intermediate/step3_merged.RData`
**Time:** ~3 minutes
**Memory:** ~2 GB

### Step 4: Add Geographic Data
**What it does:** Geocodes addresses and links to counties/MSAs
**Input:** Output from Step 3
**Output:** `data/intermediate/step4_with_geography.RData`
**Time:** ~10 minutes (geocoding is slow)
**Memory:** ~3 GB

### Step 5: Match Missing SOC Codes
**What it does:** Uses Python ML to fill in missing occupation codes
**Input:** Output from Step 4
**Output:** `data/intermediate/step5_with_soc.RData`
**Time:** ~5 minutes
**Memory:** ~2 GB
**Requires:** Python with scikit-learn

### Step 6: Adjust Wages & Merge OFLC
**What it does:** Inflation-adjusts wages and adds OFLC wage levels
**Input:** Output from Step 5
**Output:** `data/intermediate/step6_with_wages.RData`
**Time:** ~3 minutes
**Memory:** ~2 GB

### Step 7: Final Cleanup & Export
**What it does:** Removes duplicates, selects final columns, saves CSV
**Input:** Output from Step 6
**Output:** `data/intermediate/h1b_fy21_24_cleaned.csv`
**Time:** ~2 minutes
**Memory:** ~1 GB

## How to Run

### Option 1: Run Everything (Recommended for first time)
```r
source("run_pipeline_simple.R")
```

### Option 2: Run Individual Steps
```r
# Run just Step 1
source("scripts/simple/step1_process_lca.R")

# Run just Step 3 (must run 1 & 2 first)
source("scripts/simple/step3_merge_data.R")
```

### Option 3: Skip Completed Steps
The pipeline automatically detects completed steps and skips them. To re-run a step, delete its checkpoint file.

## Troubleshooting

### "R Session Aborted" / Memory Issues
1. Close other applications (especially browsers)
2. Run `rm(list=ls()); gc()` in R console
3. Restart RStudio
4. Run steps individually instead of all at once

### "Python script failed"
1. Check Python packages: `python3 -c "import sklearn"`
2. Install if needed: `pip3 install scikit-learn pandas numpy`

### "File not found"
1. Check data symlinks: `ls -la data/raw/`
2. Run: `bash link_existing_data.sh` if needed

## Current Status

Run this to check which steps are complete:
```r
source("check_pipeline_status.R")
```

## Memory Tips

Each step cleans up after itself, but you can help by:
- Running steps individually
- Restarting R between major steps
- Closing browser tabs and other applications
- Running `gc()` in R console periodically
