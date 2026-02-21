# Charts Information

## Current Situation

The wage premium analysis script (`03_wage_premium_analysis.R`) creates **28 charts** but currently only key charts are automatically saved.

## Saved Charts

All individual control-level charts are now auto-saved to `output/figures/`:

### Individual Control-Level Charts (10 charts)
1. **`01_share_positive_age_only.png`** - Share with positive premium (age only control)
2. **`02_avg_premium_age_only.png`** - Average premium (age only control)
3. **`03_share_positive_age_education.png`** - Share with positive premium (age + education)
4. **`04_avg_premium_age_education.png`** - Average premium (age + education)
5. **`05_share_positive_age_occupation.png`** - Share with positive premium (age + occupation)
6. **`06_avg_premium_age_occupation.png`** - Average premium (age + occupation)
7. **`07_share_positive_full_controls.png`** - Share with positive premium (full controls)
8. **`08_avg_premium_full_controls.png`** - Average premium (full controls)
9. **`09_share_positive_full_puma.png`** - Share with positive premium (full + PUMA)
10. **`10_avg_premium_full_puma.png`** - Average premium (full + PUMA)

### Summary Chart
11. **`comparison_all_controls.png`** - **KEY CHART**: Compares all 5 control levels including PUMA

## All 28 Charts Created

The script creates these chart categories:

### Basic Comparisons (Age Controls)
- Share with positive premium by age (age only)
- Average premium by age (age only)
- Share with positive premium by age (age + education)
- Average premium by age (age + education)
- Share with positive premium by age (age + occupation)
- Average premium by age (age + occupation)
- Share with positive premium by age (full controls)
- Average premium by age (full controls)

### Occupation Analysis
- Top 20 occupations by H-1B count
- Premium by occupation (top 20)
- Premium by occupation (detailed for top 10)
- Wage distributions for specific occupations

### Education Analysis
- Premium by education level
- Distribution across education levels

### Industry Analysis
- Premium by industry (top industries)
- Distribution across industries

### Employer Analysis
- Large employers ranked by premium
- Outsourcers vs other employers
- Premium distribution by employer type

### Wage Level Analysis
- Distribution of OFLC wage levels
- Premium by wage level
- Level III+ workers analysis

### Multi-Control Comparisons
- **Comparison of all 5 control levels** (INCLUDING PUMA!)
- Summary statistics by control level

## How to Generate Charts

Simply run the wage premium analysis script:
```r
source('scripts/03_wage_premium_analysis.R')
```

All 10 individual control-level charts will be automatically saved to `output/figures/`.

You can also view charts interactively by running the script in RStudio - charts will display in the Plots pane as they're created.

## Most Important Charts

For publication/presentation, focus on:

1. **`comparison_all_controls.png`** - Shows how controls affect premium (all 5 control levels)
2. **`08_avg_premium_full_controls.png`** - Shows lifecycle wage patterns with full controls
3. **`07_share_positive_full_controls.png`** - Shows share earning premium with full controls
4. **`10_avg_premium_full_puma.png`** - Most granular analysis (includes PUMA geographic controls)
5. **Other charts** - Occupation rankings, education analysis, employer comparisons (created but not auto-saved)

## Notes

- PUMA control is included in the comparison chart
- Match rates for PUMA control are shown in console output
- Summary statistics are saved to `output/tables/summary_by_control.csv`
