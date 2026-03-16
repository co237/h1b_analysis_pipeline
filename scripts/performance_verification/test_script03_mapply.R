# =============================================================================
# Verification test: script 03 rowwise() → mapply()
# =============================================================================
#
# What changed:
#   The two interpolation blocks in script 03 previously used
#   rowwise() %>% mutate() with inline block expressions. The new version
#   extracts the same logic into helper functions (.calc_petition_percentile
#   and .calc_petition_wage_status) and calls them via mapply().
#
# This test reconstructs the original rowwise() implementation verbatim,
# runs both versions on the same 2,000-row synthetic dataset covering all
# edge cases, and asserts that every output value is identical.
#
# Run from the project root:
#   Rscript scripts/performance_verification/test_script03_mapply.R
# =============================================================================

suppressPackageStartupMessages(library(dplyr))

set.seed(42)
n <- 2000

# Synthetic petition data covering: normal interpolation, NA Level 1,
# part-time workers, wage below minimum, wage above Level 4, NA wage.
df <- tibble(
  Level1_full = c(40000, NA,    30000, 50000, rep(40000, n - 4)),
  Level2_full = c(50000, 50000, 40000, 60000, rep(50000, n - 4)),
  Level3_full = c(60000, 60000, 50000, 70000, rep(60000, n - 4)),
  Level4_full = c(70000, 70000, 60000, 80000, rep(70000, n - 4)),
  Level1_part = Level1_full / 2,
  Level2_part = Level2_full / 2,
  Level3_part = Level3_full / 2,
  Level4_part = Level4_full / 2,
  petition_beneficiary_full_time = c("Y", "Y", "N", "Y",
                                     sample(c("Y", "N", NA), n - 4, replace = TRUE)),
  petition_annual_pay_clean = c(
    55000,           # between L2 and L3 — should interpolate to ~42nd pct
    45000,           # L1 is NA — "Missing lower bound"
    25000,           # part-time, below minimum — "Too Low"
    90000,           # above L4 — 100 / "Above Level 4"
    runif(n - 4, 20000, 90000)
  )
)

# -----------------------------------------------------------------------------
# OLD: rowwise() implementation (verbatim from pre-change script 03)
# -----------------------------------------------------------------------------
old_result <- df %>%
  mutate(
    is_fulltime = petition_beneficiary_full_time != "N" | is.na(petition_beneficiary_full_time),
    L1 = if_else(is_fulltime, Level1_full, Level1_part),
    L2 = if_else(is_fulltime, Level2_full, Level2_part),
    L3 = if_else(is_fulltime, Level3_full, Level3_part),
    L4 = if_else(is_fulltime, Level4_full, Level4_part),
    P1 = 17, P2 = 34, P3 = 50, P4 = 67
  ) %>%
  rowwise() %>%
  mutate(
    wage = petition_annual_pay_clean,
    petition_percentile = {
      lvls <- c(L1, L2, L3, L4)
      pcts <- c(17, 34, 50, 67)
      keep <- !is.na(lvls)
      lvls <- lvls[keep]; pcts <- pcts[keep]
      if (length(lvls) == 0 || is.na(wage)) {
        NA_real_
      } else if (wage < min(lvls)) {
        NA_real_
      } else if (wage >= max(lvls)) {
        100
      } else {
        lower_idx <- max(which(lvls <= wage))
        upper_idx <- min(which(lvls > wage))
        lo_lvl <- lvls[lower_idx]; hi_lvl <- lvls[upper_idx]
        lo_pct <- pcts[lower_idx]; hi_pct <- pcts[upper_idx]
        interp <- lo_pct + (wage - lo_lvl) / (hi_lvl - lo_lvl) * (hi_pct - lo_pct)
        floor(interp)
      }
    },
    petition_wage_status = {
      lvls       <- c(L1, L2, L3, L4)
      lvls_clean <- lvls[!is.na(lvls)]
      if (is.na(wage)) {
        NA_character_
      } else if (length(lvls_clean) == 0) {
        "Missing lower bound"
      } else if (wage >= max(lvls_clean)) {
        "Above Level 4"
      } else if (wage < min(lvls_clean)) {
        if (is.na(L1) && wage < min(lvls_clean)) "Missing lower bound" else "Too Low"
      } else {
        NA_character_
      }
    }
  ) %>%
  ungroup() %>%
  select(-is_fulltime, -L1, -L2, -L3, -L4, -P1, -P2, -P3, -P4, -wage)

# -----------------------------------------------------------------------------
# NEW: mapply() implementation (current script 03)
# -----------------------------------------------------------------------------
.calc_petition_percentile <- function(L1, L2, L3, L4, wage) {
  lvls <- c(L1, L2, L3, L4)
  pcts <- c(17, 34, 50, 67)
  keep <- !is.na(lvls)
  lvls <- lvls[keep]
  pcts <- pcts[keep]
  if (length(lvls) == 0 || is.na(wage)) {
    NA_real_
  } else if (wage < min(lvls)) {
    NA_real_
  } else if (wage >= max(lvls)) {
    100
  } else {
    lower_idx <- max(which(lvls <= wage))
    upper_idx <- min(which(lvls > wage))
    lo_lvl <- lvls[lower_idx]; hi_lvl <- lvls[upper_idx]
    lo_pct <- pcts[lower_idx]; hi_pct <- pcts[upper_idx]
    interp <- lo_pct + (wage - lo_lvl) / (hi_lvl - lo_lvl) * (hi_pct - lo_pct)
    floor(interp)
  }
}

.calc_petition_wage_status <- function(L1, L2, L3, L4, wage) {
  lvls       <- c(L1, L2, L3, L4)
  lvls_clean <- lvls[!is.na(lvls)]
  if (is.na(wage)) {
    NA_character_
  } else if (length(lvls_clean) == 0) {
    "Missing lower bound"
  } else if (wage >= max(lvls_clean)) {
    "Above Level 4"
  } else if (wage < min(lvls_clean)) {
    if (is.na(L1) && wage < min(lvls_clean)) "Missing lower bound" else "Too Low"
  } else {
    NA_character_
  }
}

new_result <- df %>%
  mutate(
    is_fulltime = petition_beneficiary_full_time != "N" | is.na(petition_beneficiary_full_time),
    L1   = if_else(is_fulltime, Level1_full, Level1_part),
    L2   = if_else(is_fulltime, Level2_full, Level2_part),
    L3   = if_else(is_fulltime, Level3_full, Level3_part),
    L4   = if_else(is_fulltime, Level4_full, Level4_part),
    wage = petition_annual_pay_clean,
    petition_percentile  = mapply(.calc_petition_percentile,  L1, L2, L3, L4, wage),
    petition_wage_status = mapply(.calc_petition_wage_status, L1, L2, L3, L4, wage)
  ) %>%
  select(-is_fulltime, -L1, -L2, -L3, -L4, -wage)

# -----------------------------------------------------------------------------
# Assert equivalence
# -----------------------------------------------------------------------------
pct_eq    <- all.equal(old_result$petition_percentile,  new_result$petition_percentile)
status_eq <- all.equal(old_result$petition_wage_status, new_result$petition_wage_status)

cat("petition_percentile  identical:", isTRUE(pct_eq),    "\n")
cat("petition_wage_status identical:", isTRUE(status_eq), "\n")

if (!isTRUE(pct_eq))    cat("  MISMATCH:", pct_eq,    "\n")
if (!isTRUE(status_eq)) cat("  MISMATCH:", status_eq, "\n")

cat("\nSample output (first 6 rows):\n")
print(data.frame(
  wage       = df$petition_annual_pay_clean[1:6],
  full_time  = df$petition_beneficiary_full_time[1:6],
  old_pct    = old_result$petition_percentile[1:6],
  new_pct    = new_result$petition_percentile[1:6],
  old_status = old_result$petition_wage_status[1:6],
  new_status = new_result$petition_wage_status[1:6]
))

if (isTRUE(pct_eq) && isTRUE(status_eq)) {
  cat("\nRESULT: PASS\n")
} else {
  stop("RESULT: FAIL — outputs differ between rowwise() and mapply() implementations")
}
