# Quick Start Guide - Simplified Pipeline

## What Changed?

I've restructured the pipeline to be **clearer and more reliable**:

### Old Structure (Complex)
- ❌ One massive 1,348-line script that does everything
- ❌ No checkpoints - if it crashes, start over
- ❌ Hard to understand what's happening
- ❌ Memory issues cause crashes

### New Structure (Simple)
- ✅ Clear, numbered steps that are easy to follow
- ✅ Checkpoints after each step - never lose progress
- ✅ Verbose logging so you know what's happening
- ✅ Memory cleanup between steps
- ✅ Can run steps individually for debugging

## How to Use It

### Option 1: Run Everything (Recommended)

```r
source("run_pipeline_simple.R")
```

This will:
1. Check which steps are already done
2. Skip completed steps automatically
3. Run remaining steps with clear progress messages
4. Save checkpoints after each step

###Option 2: Check Status First

```r
source("check_pipeline_status.R")
```

This shows which steps are complete and which need to run.

### Option 3: Run Individual Steps

If a step crashes or you want to understand what's happening:

```r
# Process LCA data only
source("scripts/simple/step1_process_lca.R")

# Process FOIA data only
source("scripts/simple/step2_process_foia.R")

# etc...
```

## The Steps

| Step | What It Does | Time | Memory | Can Skip? |
|------|--------------|------|--------|-----------|
| 1 | Load & clean LCA data (2015-2024) | ~5 min | ~2 GB | Yes ✓ |
| 2 | Load & clean FOIA petitions | ~2 min | ~1 GB | Yes ✓ |
| 3 | Merge data, geocode, match SOC codes | ~20 min | ~3 GB | Yes ✓ |
| 4 | Geocode to PUMAs | ~5 min | ~1 GB | Yes ✓ |
| 5 | Wage premium analysis | ~5 min | ~2 GB | No |

**Total time:** ~30-40 minutes (but you only run it once!)

## If Something Crashes

### R Session Aborted?

**Don't panic!** Your progress is saved. Just:

1. **Free up memory:**
   ```r
   rm(list=ls())
   gc()
   ```

2. **Close other apps** (especially browser tabs)

3. **Run again:**
   ```r
   source("run_pipeline_simple.R")
   ```

   It will skip completed steps and continue where it left off.

### Want to Re-Run a Step?

Delete the checkpoint file:

```r
# Re-run Step 1
file.remove("data/intermediate/step1_lca_processed.RData")

# Then run the step
source("scripts/simple/step1_process_lca.R")
```

## Understanding the Output

### Checkpoint Files (in `data/intermediate/`)

| File | What It Contains | When Created |
|------|------------------|--------------|
| `step1_lca_processed.RData` | LCA data 2015-2024 | After Step 1 |
| `step2_foia_processed.RData` | FOIA petitions 2021-2024 | After Step 2 |
| `h1b_fy21_24_cleaned.csv` | Merged & cleaned data | After Step 3 |

### Final Outputs (in `data/processed/` and `output/`)

| File | What It Contains |
|------|------------------|
| `data/processed/h1b_fy21_24_with_pumas.csv` | H-1B data with PUMA codes |
| `output/figures/*.png` | Wage premium visualizations |
| `output/tables/*.csv` | Analysis results |

## Common Issues

### Issue: "Cannot find config.R"
**Fix:** Make sure you're running from the project root directory
```r
# Option 1: Open dol-nprm-analysis.Rproj in RStudio (recommended)
# Option 2: Set working directory manually
setwd("path/to/dol-nprm-analysis")
```

### Issue: "File not found: FOIA Data/..."
**Fix:** Check your symlinks
```bash
cd data/raw
ls -la
```

You should see symlinks to your original data:
- `FOIA Data -> ~/Documents/Github/h1b-npv-wage-ranking-simulations/Data/FOIA Data`
- `LCA_Data` (actual directory)
- `Other Data -> ~/Documents/Github/h1b-npv-wage-ranking-simulations/Data/Other Data`

### Issue: Python script errors
**Fix:** Make sure scikit-learn is installed
```bash
pip3 install scikit-learn pandas numpy
```

## Advantages of the New Structure

1. **Clearer:** Each step has a clear purpose explained at the top
2. **Safer:** Checkpoints mean you never lose progress
3. **Debuggable:** Can run and test individual steps
4. **Memory-efficient:** Cleanup between steps prevents crashes
5. **Skip-able:** Don't re-run steps that already worked

## Next Steps

1. **Run the pipeline:**
   ```r
   source("run_pipeline_simple.R")
   ```

2. **Check progress:**
   ```r
   source("check_pipeline_status.R")
   ```

3. **View results:**
   - Figures: `output/figures/`
   - Tables: `output/tables/`

## Questions?

- See full documentation: `PIPELINE_GUIDE.md`
- Check which files exist: `ls -lh data/intermediate/`
- Monitor memory: `gc()` in R console
