# Key Differences Between Old and New Code

## **CRITICAL DIFFERENCE #1: Year Mapping**

### Old Code (h1b_wage_premium_analysis)
```r
# Line 165
YEAR = registration_lottery_year,
AGE = YEAR - registration_birth_year,
...
filter(!is.na(AGE), INCWAGE > 0,
       YEAR != 2021)  # Line 177: Filters out 2021
```

**Result:**
- FY2022 lottery → YEAR = 2022 → matched to ACS 2022
- FY2023 lottery → YEAR = 2023 → matched to ACS 2023
- FY2024 lottery → YEAR = 2024 → matched to ACS 2024 (doesn't exist!)
- Filters out YEAR != 2021, so only keeps 2022, 2023, 2024

**Wait, this doesn't work!** ACS 2024 doesn't exist. Let me check what years the ACS data actually has...

### New Code (h1b_analysis_pipeline) - Line 174
```r
# Use employment start year (prior calendar year) for matching to ACS
# FY 2022 lottery → employment in 2021, FY 2023 → 2022, FY 2024 → 2023
YEAR = registration_lottery_year - 1,
AGE = registration_lottery_year - registration_birth_year,
```

**Result:**
- FY2022 lottery → YEAR = 2021 → matched to ACS 2021
- FY2023 lottery → YEAR = 2022 → matched to ACS 2022
- FY2024 lottery → YEAR = 2023 → matched to ACS 2023

## **CRITICAL ISSUE: INCONSISTENCY IN NEW CODE!**

The NEW code has MULTIPLE year mappings in different sections:

**Line 174 (main section):** `YEAR = registration_lottery_year - 1` ✓ CORRECT

**Line 1031 (section 17):** `YEAR = registration_lottery_year` ✗ INCONSISTENT

**Line 1385 (Level III+ analysis):** `YEAR = registration_lottery_year` ✗ INCONSISTENT

**Line 1704 (Employer analysis):** `YEAR = registration_lottery_year` ✗ INCONSISTENT

**Line 1964 (Industry analysis):** `YEAR = registration_lottery_year` ✗ INCONSISTENT

## **DIFFERENCE #2: Age Grouping**

### Both codes use IDENTICAL age grouping:
```r
age_grp = cut(AGE,
              breaks = c(20, 25, 30, 35, 40, 45, 50, 55, 60, 65, Inf),
              right = FALSE, include.lowest = TRUE)
```

**Result:** [20,25), [25,30), [30,35), [35,40), [40,45), [45,50), [50,55), [55,60), [60,65), [65,Inf)

✓ NO DIFFERENCE

## **DIFFERENCE #3: Education Recoding**

### Both codes use IDENTICAL education recoding:
```r
# Old line 195, New line 195
EDUCD = if_else(EDUCD == 64, 63L, if_else(EDUCD < 63, 1L, as.integer(EDUCD)))
```

✓ NO DIFFERENCE

## **DIFFERENCE #4: Which Fiscal Years Are Included?**

### Old Code
```r
# Line 177
filter(!is.na(AGE), INCWAGE > 0, YEAR != 2021)
```
Excludes YEAR=2021, which means:
- If YEAR = registration_lottery_year, this excludes FY2021
- Keeps FY2022 (YEAR=2022), FY2023 (YEAR=2023), FY2024 (YEAR=2024)

**But wait!** The file is named `cleaned_fy_21_24_h1b_petitions_with_wage_levels2.csv`, which suggests it contains FY2021-2024. So the old code:
- Loads FY21-24
- Filters out YEAR != 2021
- But if YEAR = registration_lottery_year, then FY2021 would have YEAR=2021

This is confusing. Let me check what registration_lottery_year values exist.

### New Code
```r
# Line 178
filter(!is.na(AGE), INCWAGE > 0,
       YEAR >= 2021)  # Keep employment years 2021-2023 (FY 2022-2024)
```

Keeps YEAR >= 2021, which with `YEAR = registration_lottery_year - 1` means:
- FY2022 → YEAR=2021 ✓ kept
- FY2023 → YEAR=2022 ✓ kept
- FY2024 → YEAR=2023 ✓ kept
- FY2021 → YEAR=2020 ✗ excluded

So NEW code excludes FY2021 (which had employment starting in 2020, when we don't have ACS data).

## **LIKELY EXPLANATION FOR 35% → 37%**

### Hypothesis 1: Year Mapping Difference
- **Old:** FY2022 → ACS 2022, FY2023 → ACS 2023, FY2024 → ACS 2024(?)
- **New:** FY2022 → ACS 2021, FY2023 → ACS 2022, FY2024 → ACS 2023

If the old code really matched FY2022 to ACS 2022 (not 2021), that would create a 1-year offset throughout, which could easily cause a 2pp difference due to wage growth over time.

**But the user said the old script already matched FY2022 → ACS 2021!** This contradicts what I see in line 165 of the old code.

### Hypothesis 2: Different Fiscal Year Coverage
- If old code includes FY2021 data but new code doesn't, sample composition differs
- FY2021 might have different premium rates than FY2022-2024

### Hypothesis 3: ACS Year Availability
- Need to check: Does ACS data include 2024? If not, what happens to FY2024 in old code?

## **NEXT STEPS TO RESOLVE**

1. Check what values `registration_lottery_year` actually takes in the data
2. Check what ACS years are available (2021, 2022, 2023, 2024?)
3. Verify which H-1Bs actually get matched in each approach
4. Run both approaches side-by-side on same data to see sample sizes

## **ACTION ITEMS**

1. **Fix inconsistency in new code** - All sections should use `registration_lottery_year - 1`
2. **Verify old code's year mapping** - Does it really use lottery year directly?
3. **Check ACS data years** - What years are actually available?
4. **Run diagnostic** - Compare sample sizes at each step between old and new
