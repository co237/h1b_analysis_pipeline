# =============================================================================
# Verification test: script 04 per-row predict() loop → batched predict()
# =============================================================================
#
# What changed:
#   calculate_edu_exp_ratios() previously called feols predict() once per row
#   of the edu × exp grid (up to ~330 rows per occupation), looping over each
#   (education, experience) combination and computing a weighted average of
#   predicted wages across metro areas. The new version stacks all combinations
#   into one data frame and calls predict() a single time, then uses tapply()
#   to compute weighted sums by group.
#
# This test fits a real feols() model on 3,000 synthetic observations, runs
# both implementations, and confirms that every ratio_p50 value is identical
# (max absolute difference = 0).
#
# Run from the project root:
#   Rscript scripts/performance_verification/test_script04_vectorized_predict.R
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(fixest)
  library(Hmisc)
})

set.seed(123)

n <- 3000
education_levels <- c("Less than HS", "High school", "Some college",
                       "Bachelors", "Masters", "PhD")
met_areas <- paste0("MSA_", 1:20)

occ_data <- tibble(
  INCWAGE              = exp(rnorm(n, mean = log(60000), sd = 0.5)),
  PERWT                = sample(10:200, n, replace = TRUE),
  highest_ed           = factor(
    sample(education_levels, n, replace = TRUE, prob = c(.05, .20, .18, .30, .18, .09)),
    levels = education_levels
  ),
  Years_pot_experience = sample(0:40, n, replace = TRUE),
  MET2013              = sample(met_areas, n, replace = TRUE),
  log_wage             = log(INCWAGE)
)

model <- feols(log_wage ~ highest_ed + Years_pot_experience | MET2013,
               data = occ_data, weights = ~PERWT, warn = FALSE, notes = FALSE)

raw_median <- as.numeric(wtd.quantile(occ_data$INCWAGE,
                                       weights = occ_data$PERWT, probs = 0.50))

# -----------------------------------------------------------------------------
# OLD: per-row for-loop (verbatim from pre-change script 04)
# -----------------------------------------------------------------------------
calculate_edu_exp_ratios_OLD <- function(model, occ_data, raw_median) {
  if (is.null(model)) return(NULL)
  education_levels_observed <- unique(occ_data$highest_ed[!is.na(occ_data$highest_ed)])
  all_education_levels <- c("Less than HS", "High school", "Some college", "Associates",
                             "Bachelors", "Masters", "Prof degree", "PhD")
  education_levels <- intersect(all_education_levels, as.character(education_levels_observed))
  experience_range <- seq(0, 40, by = 1)

  edu_exp_grid <- expand.grid(
    highest_ed           = education_levels,
    Years_pot_experience = experience_range,
    stringsAsFactors     = FALSE
  )

  area_weights <- occ_data %>%
    filter(!is.na(MET2013)) %>%
    group_by(MET2013) %>%
    summarise(area_weight = sum(PERWT), .groups = "drop") %>%
    mutate(weight_prop = area_weight / sum(area_weight))

  edu_exp_grid$predicted_wage <- NA_real_
  edu_exp_grid$ratio_p50      <- NA_real_

  for (i in seq_len(nrow(edu_exp_grid))) {
    pred_data <- area_weights %>%
      mutate(
        highest_ed           = edu_exp_grid$highest_ed[i],
        Years_pot_experience = edu_exp_grid$Years_pot_experience[i]
      )
    pred_log_wage    <- predict(model, newdata = pred_data)
    pred_wage_levels <- exp(pred_log_wage)
    weighted_avg     <- sum(pred_wage_levels * pred_data$weight_prop, na.rm = TRUE)
    edu_exp_grid$predicted_wage[i] <- weighted_avg
    edu_exp_grid$ratio_p50[i]      <- weighted_avg / raw_median
  }

  edu_exp_grid %>% select(highest_ed, Years_pot_experience, ratio_p50)
}

# -----------------------------------------------------------------------------
# NEW: vectorized batched predict() (current script 04)
# -----------------------------------------------------------------------------
calculate_edu_exp_ratios_NEW <- function(model, occ_data, raw_median) {
  if (is.null(model)) return(NULL)
  education_levels_observed <- unique(occ_data$highest_ed[!is.na(occ_data$highest_ed)])
  all_education_levels <- c("Less than HS", "High school", "Some college", "Associates",
                             "Bachelors", "Masters", "Prof degree", "PhD")
  education_levels <- intersect(all_education_levels, as.character(education_levels_observed))
  experience_range <- seq(0, 40, by = 1)

  edu_exp_grid <- expand.grid(
    highest_ed           = education_levels,
    Years_pot_experience = experience_range,
    stringsAsFactors     = FALSE
  )

  area_weights <- occ_data %>%
    filter(!is.na(MET2013)) %>%
    group_by(MET2013) %>%
    summarise(area_weight = sum(PERWT), .groups = "drop") %>%
    mutate(weight_prop = area_weight / sum(area_weight))

  n_grid  <- nrow(edu_exp_grid)
  n_areas <- nrow(area_weights)

  pred_data_all <- area_weights[rep(seq_len(n_areas), times = n_grid), ]
  rownames(pred_data_all) <- NULL
  pred_data_all$highest_ed           <- rep(edu_exp_grid$highest_ed,           each = n_areas)
  pred_data_all$Years_pot_experience <- rep(edu_exp_grid$Years_pot_experience, each = n_areas)

  pred_log_wages   <- predict(model, newdata = pred_data_all)
  pred_wage_levels <- exp(pred_log_wages)
  weights_rep      <- rep(area_weights$weight_prop, times = n_grid)
  group_ids        <- rep(seq_len(n_grid),           each  = n_areas)

  weighted_avgs <- as.numeric(
    tapply(pred_wage_levels * weights_rep, group_ids, sum, na.rm = TRUE)
  )

  edu_exp_grid$predicted_wage <- weighted_avgs
  edu_exp_grid$ratio_p50      <- weighted_avgs / raw_median

  edu_exp_grid %>% select(highest_ed, Years_pot_experience, ratio_p50)
}

# -----------------------------------------------------------------------------
# Assert equivalence
# -----------------------------------------------------------------------------
cat("Running OLD (for-loop) version...\n")
result_old <- calculate_edu_exp_ratios_OLD(model, occ_data, raw_median)

cat("Running NEW (vectorized) version...\n")
result_new <- calculate_edu_exp_ratios_NEW(model, occ_data, raw_median)

grid_eq  <- all.equal(
  result_old[, c("highest_ed", "Years_pot_experience")],
  result_new[, c("highest_ed", "Years_pot_experience")]
)
ratio_eq <- all.equal(result_old$ratio_p50, result_new$ratio_p50, tolerance = 1e-10)

cat("\nGrid order identical:", isTRUE(grid_eq),  "\n")
cat("ratio_p50 identical: ", isTRUE(ratio_eq), "\n")
cat("Max absolute difference:", max(abs(result_old$ratio_p50 - result_new$ratio_p50)), "\n")

if (!isTRUE(grid_eq))  cat("  GRID MISMATCH:", grid_eq,  "\n")
if (!isTRUE(ratio_eq)) cat("  RATIO MISMATCH:", ratio_eq, "\n")

cat("\nSample output (first 8 rows):\n")
print(data.frame(
  edu     = result_old$highest_ed[1:8],
  exp     = result_old$Years_pot_experience[1:8],
  old_r50 = round(result_old$ratio_p50[1:8], 8),
  new_r50 = round(result_new$ratio_p50[1:8], 8),
  diff    = result_old$ratio_p50[1:8] - result_new$ratio_p50[1:8]
))

if (isTRUE(grid_eq) && isTRUE(ratio_eq)) {
  cat("\nRESULT: PASS\n")
} else {
  stop("RESULT: FAIL — outputs differ between for-loop and batched predict() implementations")
}
