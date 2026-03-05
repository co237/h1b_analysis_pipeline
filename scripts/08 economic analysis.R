################################################################################
# Script 08: Economic Analysis of H-1B Prevailing Wage Policies
#
# Purpose: Generate IFP-branded charts and tables for NPRM economic analysis
#
# Input:  data/processed/h1b_with_mincer_wages.csv
# Output: output/analysis/economic_analysis.pdf
#
# Author: Institute for Progress
# Date: March 2026
################################################################################

# Load required packages -------------------------------------------------------
library(tidyverse)
library(scales)
library(ggplot2)
library(gridExtra)
library(matrixStats)

# IFP Brand Colors (from IFP_style2024.css) -----------------------------------
ifp_colors <- list(
  off_white = "#fcfbeb",
  purple = "#b17ada",
  orange = "#ff9762",
  rich_black = "#373737",
  green = "#39d794",
  red = "#ff6565",
  light_blue = "#41c4fc",
  yellow = "#fbdb36",
  pink = "#ff9ee3",
  dark_blue = "#3368ce"  # Immigration category
)

# Set IFP theme for all plots --------------------------------------------------
theme_ifp <- function() {
  theme_minimal() +
    theme(
      text = element_text(color = ifp_colors$rich_black),
      plot.title = element_text(size = 16, face = "bold", color = ifp_colors$rich_black),
      plot.subtitle = element_text(size = 12, color = ifp_colors$rich_black),
      axis.title = element_text(size = 11, color = ifp_colors$rich_black),
      axis.text = element_text(size = 10, color = ifp_colors$rich_black),
      legend.title = element_text(size = 11, face = "bold"),
      legend.text = element_text(size = 10),
      panel.grid.major = element_line(color = "gray90"),
      panel.grid.minor = element_blank(),
      plot.background = element_rect(fill = ifp_colors$off_white, color = NA),
      panel.background = element_rect(fill = ifp_colors$off_white, color = NA)
    )
}

# Load data --------------------------------------------------------------------
cat("Loading H-1B petition data with Mincer wages...\n")
h1b <- read_csv("data/processed/h1b_with_mincer_wages.csv",
                show_col_types = FALSE)

cat(sprintf("Loaded %s petitions\n", format(nrow(h1b), big.mark = ",")))

# Create output directory ------------------------------------------------------
dir.create("output/analysis", showWarnings = FALSE, recursive = TRUE)

# Data preparation -------------------------------------------------------------
cat("\nPreparing data for analysis...\n")

# Filter to valid petitions with required fields
h1b_valid <- h1b %>%
  filter(
    !is.na(petition_annual_pay_clean),
    !is.na(pw_p50),
    petition_annual_pay_clean > 0,
    pw_p50 > 0
  )

cat(sprintf("Valid petitions for analysis: %s\n",
            format(nrow(h1b_valid), big.mark = ",")))

# Calculate wage premium (percent above/below 50th percentile)
h1b_valid <- h1b_valid %>%
  mutate(
    wage_premium_pct = ((petition_annual_pay_clean - pw_p50) / pw_p50) * 100,
    underpaid = petition_annual_pay_clean < pw_p50,
    age_group_5yr = case_when(
      age >= 20 & age <= 24 ~ "20-24",
      age >= 25 & age <= 29 ~ "25-29",
      age >= 30 & age <= 34 ~ "30-34",
      age >= 35 & age <= 39 ~ "35-39",
      age >= 40 & age <= 44 ~ "40-44",
      age >= 45 & age <= 49 ~ "45-49",
      age >= 50 & age <= 54 ~ "50-54",
      age >= 55 & age <= 59 ~ "55-59",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(age_group_5yr))

################################################################################
# ANALYSIS 1: Overall Underpayment Share and Median Wage Premium
################################################################################

cat("\n=== Analysis 1: Overall Underpayment ===\n")

overall_stats <- h1b_valid %>%
  summarise(
    total_petitions = n(),
    n_underpaid = sum(underpaid),
    pct_underpaid = mean(underpaid) * 100,
    median_premium = median(wage_premium_pct),
    mean_premium = mean(wage_premium_pct)
  )

cat(sprintf("Total petitions: %s\n", format(overall_stats$total_petitions, big.mark = ",")))
cat(sprintf("Underpaid (< 50th percentile): %s (%.1f%%)\n",
            format(overall_stats$n_underpaid, big.mark = ","),
            overall_stats$pct_underpaid))
cat(sprintf("Median wage premium: %.1f%%\n", overall_stats$median_premium))
cat(sprintf("Mean wage premium: %.1f%%\n", overall_stats$mean_premium))

# Create summary text plot
p1 <- ggplot() +
  annotate("text", x = 0.5, y = 0.7,
           label = sprintf("%.1f%%", overall_stats$pct_underpaid),
           size = 24, fontface = "bold", color = ifp_colors$dark_blue) +
  annotate("text", x = 0.5, y = 0.5,
           label = "of H-1B petitions pay below\nthe 50th percentile",
           size = 6, color = ifp_colors$rich_black) +
  annotate("text", x = 0.5, y = 0.2,
           label = sprintf("Median wage premium: %.1f%%", overall_stats$median_premium),
           size = 5, color = ifp_colors$rich_black, fontface = "italic") +
  xlim(0, 1) + ylim(0, 1) +
  theme_void() +
  theme(plot.background = element_rect(fill = ifp_colors$off_white, color = NA))

################################################################################
# ANALYSIS 2: Scatterplot - Salary vs Wage Premium
################################################################################

cat("\n=== Analysis 2: Salary vs Wage Premium ===\n")

# Sample for visualization (too many points otherwise)
set.seed(123)
h1b_sample <- h1b_valid %>%
  sample_n(min(20000, nrow(h1b_valid)))

p2 <- ggplot(h1b_sample, aes(x = petition_annual_pay_clean, y = wage_premium_pct)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black, linewidth = 0.5) +
  geom_point(alpha = 0.3, color = ifp_colors$dark_blue, size = 0.5) +
  geom_smooth(method = "lm", formula = y ~ x,
              color = ifp_colors$orange, se = FALSE, linewidth = 1.5) +
  scale_x_continuous(labels = dollar_format(scale = 1/1000, suffix = "K"),
                     limits = c(0, 250000)) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     limits = c(-100, 200)) +
  labs(
    title = "Salary vs Wage Premium Relative to 50th Percentile",
    x = "Annual Salary",
    y = "Wage Premium (%)"
  ) +
  theme_ifp()

################################################################################
# ANALYSIS 3: Underpayment Rates by Age Cohort
################################################################################

cat("\n=== Analysis 3: Underpayment Rates by Age Cohort ===\n")

# Calculate underpayment rates for broader age cohorts
underpayment_by_cohort <- h1b_valid %>%
  mutate(
    age_cohort = case_when(
      age >= 20 & age <= 29 ~ "20-29",
      age >= 30 & age <= 39 ~ "30-39",
      age >= 40 & age <= 49 ~ "40-49",
      age >= 50 & age <= 59 ~ "50-59",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(age_cohort)) %>%
  group_by(age_cohort) %>%
  summarise(
    n_petitions = n(),
    n_underpaid = sum(underpaid),
    pct_underpaid = mean(underpaid) * 100
  ) %>%
  arrange(age_cohort)

print(underpayment_by_cohort)

p3 <- ggplot(underpayment_by_cohort, aes(x = age_cohort, y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.1))) +
  labs(
    title = "Underpayment Rates by Age Cohort",
    subtitle = "Percentage of petitions paying below 50th percentile",
    x = "Age Cohort",
    y = "Underpaid (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 0))

################################################################################
# ANALYSIS 4: Underpayment by 5-Year Age Group
################################################################################

cat("\n=== Analysis 4: Underpayment by 5-Year Age Group ===\n")

underpayment_by_age <- h1b_valid %>%
  group_by(age_group_5yr) %>%
  summarise(
    n_petitions = n(),
    n_underpaid = sum(underpaid),
    pct_underpaid = mean(underpaid) * 100
  ) %>%
  arrange(age_group_5yr)

print(underpayment_by_age)

p4 <- ggplot(underpayment_by_age, aes(x = age_group_5yr, y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            vjust = -0.5, size = 3.5, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.1))) +
  labs(
    title = "Underpayment by 5-Year Age Group",
    subtitle = "Percentage of petitions paying below 50th percentile",
    x = "Age Group",
    y = "Underpaid (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 0))

################################################################################
# ANALYSIS 5: Median Wage Premium by 5-Year Age Group
################################################################################

cat("\n=== Analysis 5: Median Wage Premium by 5-Year Age Group ===\n")

premium_by_age <- h1b_valid %>%
  group_by(age_group_5yr) %>%
  summarise(
    n_petitions = n(),
    median_premium = median(wage_premium_pct),
    mean_premium = mean(wage_premium_pct)
  ) %>%
  arrange(age_group_5yr)

print(premium_by_age)

p5 <- ggplot(premium_by_age, aes(x = age_group_5yr, y = median_premium)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black) +
  geom_col(fill = ifp_colors$purple) +
  geom_text(aes(label = sprintf("%.1f%%", median_premium)),
            vjust = ifelse(premium_by_age$median_premium >= 0, -0.5, 1.5),
            size = 3.5, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1)) +
  labs(
    title = "Median Wage Premium by 5-Year Age Group",
    subtitle = "Percent above/below 50th percentile prevailing wage",
    x = "Age Group",
    y = "Median Premium (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 0))

################################################################################
# ANALYSIS 6: Policy Comparison - Underpayment Rates
################################################################################

cat("\n=== Analysis 6: Policy Comparison ===\n")

# Prepare data for policy comparison
h1b_policy <- h1b_valid %>%
  mutate(
    # Status Quo: All petitions with non-missing pw_p50 (which is all in h1b_valid)
    eligible_status_quo = !is.na(pw_p50),
    underpaid_status_quo = petition_annual_pay_clean < pw_p50,

    # 2021 Rule: Uses petition_percentile_combined against new thresholds
    # Level I=35th, II=53rd, III=72nd, IV=90th
    threshold_2021 = case_when(
      PW_WAGE_LEVEL == "I" ~ 35,
      PW_WAGE_LEVEL == "II" ~ 53,
      PW_WAGE_LEVEL == "III" ~ 72,
      PW_WAGE_LEVEL == "IV" ~ 90,
      TRUE ~ NA_real_
    ),
    eligible_2021 = !is.na(threshold_2021) &
                    !is.na(petition_percentile_combined) &
                    petition_percentile_combined >= threshold_2021,
    underpaid_2021 = eligible_2021 & petition_annual_pay_clean < pw_p50,

    # 50th Percentile Uniform: petition_percentile_combined must be >= 50
    eligible_p50 = !is.na(petition_percentile_combined) & petition_percentile_combined >= 50,
    underpaid_p50 = eligible_p50 & petition_annual_pay_clean < pw_p50,

    # Experience Benchmarking: Simply eligible if pay >= pw_p50
    eligible_eb = petition_annual_pay_clean >= pw_p50,
    underpaid_eb = FALSE  # By definition, all eligible meet pw_p50
  )

# Calculate policy statistics
policy_stats <- tibble(
  policy = factor(c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"),
                  levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"))
) %>%
  mutate(
    n_eligible = c(
      sum(h1b_policy$eligible_status_quo, na.rm = TRUE),
      sum(h1b_policy$eligible_2021, na.rm = TRUE),
      sum(h1b_policy$eligible_p50, na.rm = TRUE),
      sum(h1b_policy$eligible_eb, na.rm = TRUE)
    ),
    n_underpaid = c(
      sum(h1b_policy$underpaid_status_quo, na.rm = TRUE),
      sum(h1b_policy$underpaid_2021, na.rm = TRUE),
      sum(h1b_policy$underpaid_p50, na.rm = TRUE),
      sum(h1b_policy$underpaid_eb, na.rm = TRUE)
    ),
    pct_underpaid = (n_underpaid / n_eligible) * 100,
    pct_eligible = (n_eligible / nrow(h1b_policy)) * 100
  )

print(policy_stats)

# Bar chart comparing underpayment rates
p6 <- ggplot(policy_stats, aes(x = policy, y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Underpayment Rates by Policy",
    subtitle = "Percentage of eligible petitions paying below 50th percentile",
    x = NULL,
    y = "Underpaid Among Eligible (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 7: Policy Comparison Table
################################################################################

cat("\n=== Analysis 7: Policy Comparison Table ===\n")

# Calculate baseline totals (Status Quo)
total_n <- nrow(h1b_policy)
total_underpaid <- sum(h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE)
total_positive_premium <- sum(h1b_policy$petition_annual_pay_clean >= h1b_policy$pw_p50, na.rm = TRUE)

cat(sprintf("Total petitions: %s\n", format(total_n, big.mark = ",")))
cat(sprintf("Total underpaid (< pw_p50): %s\n", format(total_underpaid, big.mark = ",")))
cat(sprintf("Total positive premium (>= pw_p50): %s\n", format(total_positive_premium, big.mark = ",")))

# Calculate policy-specific metrics
policy_table_data <- tibble(
  Policy = factor(c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"),
                  levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking")),

  # Column 1: Share of petitions made ineligible
  ineligible_n = c(
    sum(!h1b_policy$eligible_status_quo, na.rm = TRUE),
    sum(!h1b_policy$eligible_2021, na.rm = TRUE),
    sum(!h1b_policy$eligible_p50, na.rm = TRUE),
    sum(!h1b_policy$eligible_eb, na.rm = TRUE)
  ),

  # Column 2: False Negatives - Eligible underpaid / all underpaid
  # (underpaid workers who pass the policy test)
  eligible_underpaid_n = c(
    sum(h1b_policy$eligible_status_quo & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE),
    sum(h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE),
    sum(h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE),
    sum(h1b_policy$eligible_eb & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE)
  ),

  # Column 3: False Positives - Ineligible positive premium / all positive premium
  # (positive premium workers who fail the policy test)
  ineligible_positive_n = c(
    sum(!h1b_policy$eligible_status_quo & h1b_policy$petition_annual_pay_clean >= h1b_policy$pw_p50, na.rm = TRUE),
    sum(!h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean >= h1b_policy$pw_p50, na.rm = TRUE),
    sum(!h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean >= h1b_policy$pw_p50, na.rm = TRUE),
    sum(!h1b_policy$eligible_eb & h1b_policy$petition_annual_pay_clean >= h1b_policy$pw_p50, na.rm = TRUE)
  )
) %>%
  mutate(
    `% Ineligible` = sprintf("%.1f%%", (ineligible_n / total_n) * 100),
    `False Negatives` = sprintf("%.1f%%", (eligible_underpaid_n / total_underpaid) * 100),
    `False Positives` = sprintf("%.1f%%", (ineligible_positive_n / total_positive_premium) * 100)
  ) %>%
  select(Policy, `% Ineligible`, `False Negatives`, `False Positives`)

print(policy_table_data)

# Create table as a ggplot object for PDF
table_grob <- tableGrob(policy_table_data, rows = NULL,
                        theme = ttheme_minimal(
                          core = list(
                            fg_params = list(hjust = 0, x = 0.1, fontsize = 10),
                            bg_params = list(fill = ifp_colors$off_white)
                          ),
                          colhead = list(
                            fg_params = list(fontface = "bold", fontsize = 11),
                            bg_params = list(fill = ifp_colors$rich_black, col = ifp_colors$off_white)
                          )
                        ))

p7 <- ggplot() +
  annotation_custom(table_grob) +
  labs(title = "Policy Comparison Summary") +
  theme_void() +
  theme(
    plot.title = element_text(size = 16, face = "bold", hjust = 0.5,
                              color = ifp_colors$rich_black, margin = margin(b = 10)),
    plot.background = element_rect(fill = ifp_colors$off_white, color = NA)
  )

################################################################################
# ANALYSIS 8: Median Underpayment ($) Among Underpaid by Policy
################################################################################

cat("\n=== Analysis 8: Median Underpayment ($) by Policy ===\n")

# Calculate median underpayment in dollars for underpaid workers under each policy
median_underpay_dollars <- tibble(
  Policy = factor(c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"),
                  levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking")),

  median_underpay = c(
    # Status Quo: all underpaid workers
    median(h1b_policy$petition_annual_pay_clean[h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
           h1b_policy$pw_p50[h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50], na.rm = TRUE),

    # 2021 Rule: eligible and underpaid
    median(h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
           h1b_policy$pw_p50[h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50], na.rm = TRUE),

    # 50th Percentile: eligible and underpaid
    median(h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
           h1b_policy$pw_p50[h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50], na.rm = TRUE),

    # Experience Benchmarking: no underpaid workers by definition
    0
  )
)

print(median_underpay_dollars)

p8 <- ggplot(median_underpay_dollars, aes(x = Policy, y = median_underpay)) +
  geom_col(fill = ifp_colors$red) +
  geom_text(aes(label = dollar(median_underpay, accuracy = 1)),
            vjust = 1.5, size = 4, color = ifp_colors$off_white) +
  scale_y_continuous(labels = dollar_format(),
                     expand = expansion(mult = c(0.1, 0.05))) +
  labs(
    title = "Median Underpayment Among Underpaid Workers by Policy",
    subtitle = "Dollar amount below 50th percentile (negative values)",
    x = NULL,
    y = "Median Underpayment ($)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 9: Median Underpayment (%) Among Underpaid by Policy
################################################################################

cat("\n=== Analysis 9: Median Underpayment (%) by Policy ===\n")

# Calculate median underpayment in percent for underpaid workers under each policy
median_underpay_pct <- tibble(
  Policy = factor(c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"),
                  levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking")),

  median_underpay_pct = c(
    # Status Quo
    median(((h1b_policy$pw_p50[h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
             h1b_policy$petition_annual_pay_clean[h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) /
            h1b_policy$pw_p50[h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) * 100, na.rm = TRUE),

    # 2021 Rule
    median(((h1b_policy$pw_p50[h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
             h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) /
            h1b_policy$pw_p50[h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) * 100, na.rm = TRUE),

    # 50th Percentile
    median(((h1b_policy$pw_p50[h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
             h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) /
            h1b_policy$pw_p50[h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) * 100, na.rm = TRUE),

    # Experience Benchmarking
    0
  )
)

print(median_underpay_pct)

p9 <- ggplot(median_underpay_pct, aes(x = Policy, y = median_underpay_pct)) +
  geom_col(fill = ifp_colors$red) +
  geom_text(aes(label = sprintf("%.1f%%", median_underpay_pct)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Median Underpayment Among Underpaid Workers by Policy",
    subtitle = "Percent below 50th percentile (positive values)",
    x = NULL,
    y = "Median Underpayment (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 10: Median Wage Premium ($) Among Eligible by Policy
################################################################################

cat("\n=== Analysis 10: Median Wage Premium ($) by Policy ===\n")

# Calculate median wage premium in dollars for all eligible workers under each policy
median_premium_dollars <- tibble(
  Policy = factor(c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"),
                  levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking")),

  median_premium = c(
    # Status Quo: all workers
    median(h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_status_quo] -
           h1b_policy$pw_p50[h1b_policy$eligible_status_quo], na.rm = TRUE),

    # 2021 Rule: eligible workers
    median(h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_2021] -
           h1b_policy$pw_p50[h1b_policy$eligible_2021], na.rm = TRUE),

    # 50th Percentile: eligible workers
    median(h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_p50] -
           h1b_policy$pw_p50[h1b_policy$eligible_p50], na.rm = TRUE),

    # Experience Benchmarking: eligible workers (all have positive premium)
    median(h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_eb] -
           h1b_policy$pw_p50[h1b_policy$eligible_eb], na.rm = TRUE)
  )
)

print(median_premium_dollars)

p10 <- ggplot(median_premium_dollars, aes(x = Policy, y = median_premium)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black) +
  geom_col(aes(fill = median_premium >= 0)) +
  scale_fill_manual(values = c("TRUE" = ifp_colors$green, "FALSE" = ifp_colors$red), guide = "none") +
  geom_text(aes(label = dollar(median_premium, accuracy = 1)),
            vjust = ifelse(median_premium_dollars$median_premium >= 0, -0.5, 1.5),
            size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = dollar_format()) +
  labs(
    title = "Median Wage Premium Among Eligible Workers by Policy",
    subtitle = "Dollar amount above/below 50th percentile",
    x = NULL,
    y = "Median Wage Premium ($)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 11: Median Wage Premium (%) Among Eligible by Policy
################################################################################

cat("\n=== Analysis 11: Median Wage Premium (%) by Policy ===\n")

# Calculate median wage premium in percent for all eligible workers under each policy
median_premium_pct <- tibble(
  Policy = factor(c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"),
                  levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking")),

  median_premium_pct = c(
    # Status Quo
    median(((h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_status_quo] -
             h1b_policy$pw_p50[h1b_policy$eligible_status_quo]) /
            h1b_policy$pw_p50[h1b_policy$eligible_status_quo]) * 100, na.rm = TRUE),

    # 2021 Rule
    median(((h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_2021] -
             h1b_policy$pw_p50[h1b_policy$eligible_2021]) /
            h1b_policy$pw_p50[h1b_policy$eligible_2021]) * 100, na.rm = TRUE),

    # 50th Percentile
    median(((h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_p50] -
             h1b_policy$pw_p50[h1b_policy$eligible_p50]) /
            h1b_policy$pw_p50[h1b_policy$eligible_p50]) * 100, na.rm = TRUE),

    # Experience Benchmarking
    median(((h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_eb] -
             h1b_policy$pw_p50[h1b_policy$eligible_eb]) /
            h1b_policy$pw_p50[h1b_policy$eligible_eb]) * 100, na.rm = TRUE)
  )
)

print(median_premium_pct)

p11 <- ggplot(median_premium_pct, aes(x = Policy, y = median_premium_pct)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black) +
  geom_col(aes(fill = median_premium_pct >= 0)) +
  scale_fill_manual(values = c("TRUE" = ifp_colors$green, "FALSE" = ifp_colors$red), guide = "none") +
  geom_text(aes(label = sprintf("%.1f%%", median_premium_pct)),
            vjust = ifelse(median_premium_pct$median_premium_pct >= 0, -0.5, 1.5),
            size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1)) +
  labs(
    title = "Median Wage Premium Among Eligible Workers by Policy",
    subtitle = "Percent above/below 50th percentile",
    x = NULL,
    y = "Median Wage Premium (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 12: Median Salary of Eligible Workers by Year and Policy
################################################################################

cat("\n=== Analysis 12: Median Salary by Year and Policy ===\n")

# Calculate median salary for eligible workers under each policy by year
salary_by_year_median <- h1b_policy %>%
  filter(!is.na(PW_year)) %>%
  summarise(
    across(c(eligible_status_quo, eligible_2021, eligible_p50, eligible_eb),
           ~list(tibble(
             year = PW_year,
             eligible = .x,
             salary = petition_annual_pay_clean
           ))),
    .groups = "drop"
  ) %>%
  pivot_longer(everything(), names_to = "policy", values_to = "data") %>%
  unnest(data) %>%
  filter(eligible) %>%
  group_by(policy, year) %>%
  summarise(
    median_salary = median(salary, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    policy = factor(case_when(
      policy == "eligible_status_quo" ~ "Status Quo",
      policy == "eligible_2021" ~ "2021 Rule",
      policy == "eligible_p50" ~ "50th Percentile Minimum",
      policy == "eligible_eb" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"))
  )

print(salary_by_year_median)

p12 <- ggplot(salary_by_year_median, aes(x = year, y = median_salary, color = policy, group = policy)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  scale_color_manual(values = c(
    "Status Quo" = ifp_colors$rich_black,
    "2021 Rule" = ifp_colors$purple,
    "50th Percentile Minimum" = ifp_colors$orange,
    "Experience Benchmarking" = ifp_colors$dark_blue
  )) +
  scale_y_continuous(labels = dollar_format(scale = 1/1000, suffix = "K")) +
  scale_x_continuous(breaks = 2021:2023) +
  labs(
    title = "Median Salary of Eligible Workers by Year",
    subtitle = "Comparing policy proposals across fiscal years",
    x = "Fiscal Year",
    y = "Median Salary",
    color = "Policy"
  ) +
  theme_ifp() +
  theme(legend.position = "bottom")

################################################################################
# ANALYSIS 13: Mean Salary of Eligible Workers by Year and Policy
################################################################################

cat("\n=== Analysis 13: Mean Salary by Year and Policy ===\n")

# Calculate mean salary for eligible workers under each policy by year
salary_by_year_mean <- h1b_policy %>%
  filter(!is.na(PW_year)) %>%
  summarise(
    across(c(eligible_status_quo, eligible_2021, eligible_p50, eligible_eb),
           ~list(tibble(
             year = PW_year,
             eligible = .x,
             salary = petition_annual_pay_clean
           ))),
    .groups = "drop"
  ) %>%
  pivot_longer(everything(), names_to = "policy", values_to = "data") %>%
  unnest(data) %>%
  filter(eligible) %>%
  group_by(policy, year) %>%
  summarise(
    mean_salary = mean(salary, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    policy = factor(case_when(
      policy == "eligible_status_quo" ~ "Status Quo",
      policy == "eligible_2021" ~ "2021 Rule",
      policy == "eligible_p50" ~ "50th Percentile Minimum",
      policy == "eligible_eb" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"))
  )

print(salary_by_year_mean)

p13 <- ggplot(salary_by_year_mean, aes(x = year, y = mean_salary, color = policy, group = policy)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  scale_color_manual(values = c(
    "Status Quo" = ifp_colors$rich_black,
    "2021 Rule" = ifp_colors$purple,
    "50th Percentile Minimum" = ifp_colors$orange,
    "Experience Benchmarking" = ifp_colors$dark_blue
  )) +
  scale_y_continuous(labels = dollar_format(scale = 1/1000, suffix = "K")) +
  scale_x_continuous(breaks = 2021:2023) +
  labs(
    title = "Mean Salary of Eligible Workers by Year",
    subtitle = "Comparing policy proposals across fiscal years",
    x = "Fiscal Year",
    y = "Mean Salary",
    color = "Policy"
  ) +
  theme_ifp() +
  theme(legend.position = "bottom")

################################################################################
# ANALYSIS 14: Age Distribution of Eligible Workers by Policy
################################################################################

cat("\n=== Analysis 14: Age Distribution by Policy ===\n")

# Calculate age statistics for eligible workers under each policy
age_stats_by_policy <- h1b_policy %>%
  filter(!is.na(age)) %>%
  summarise(
    across(c(eligible_status_quo, eligible_2021, eligible_p50, eligible_eb),
           ~list(tibble(
             age = age,
             eligible = .x
           ))),
    .groups = "drop"
  ) %>%
  pivot_longer(everything(), names_to = "policy", values_to = "data") %>%
  unnest(data) %>%
  filter(eligible) %>%
  mutate(
    policy = factor(case_when(
      policy == "eligible_status_quo" ~ "Status Quo",
      policy == "eligible_2021" ~ "2021 Rule",
      policy == "eligible_p50" ~ "50th Percentile Minimum",
      policy == "eligible_eb" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"))
  )

# Calculate summary statistics
age_summary <- age_stats_by_policy %>%
  group_by(policy) %>%
  summarise(
    median_age = median(age, na.rm = TRUE),
    p25_age = quantile(age, 0.25, na.rm = TRUE),
    p75_age = quantile(age, 0.75, na.rm = TRUE),
    .groups = "drop"
  )

print(age_summary)

# Create faceted histogram with summary statistics
p14 <- ggplot(age_stats_by_policy, aes(x = age)) +
  geom_histogram(binwidth = 2, fill = ifp_colors$dark_blue, color = "white") +
  geom_vline(data = age_summary, aes(xintercept = median_age),
             color = ifp_colors$orange, linewidth = 1, linetype = "solid") +
  geom_vline(data = age_summary, aes(xintercept = p25_age),
             color = ifp_colors$purple, linewidth = 0.8, linetype = "dashed") +
  geom_vline(data = age_summary, aes(xintercept = p75_age),
             color = ifp_colors$purple, linewidth = 0.8, linetype = "dashed") +
  geom_text(data = age_summary,
            aes(x = 55, y = Inf,
                label = sprintf("Median: %.0f\nP25: %.0f | P75: %.0f",
                               median_age, p25_age, p75_age)),
            vjust = 1.5, hjust = 1, size = 3, color = ifp_colors$rich_black) +
  facet_wrap(~policy, ncol = 2, scales = "free_y") +
  scale_x_continuous(limits = c(20, 60), breaks = seq(20, 60, 10)) +
  labs(
    title = "Age Distribution of Eligible Workers by Policy",
    subtitle = "Solid line = median, dashed lines = 25th and 75th percentiles",
    x = "Age",
    y = "Count"
  ) +
  theme_ifp() +
  theme(strip.text = element_text(face = "bold", size = 10))

################################################################################
# ANALYSIS 15: Weighted Lottery Simulation - Assign Weights
################################################################################

cat("\n=== Analysis 15: Weighted Lottery Simulation ===\n")

# Assign lottery weights based on each policy's criteria
h1b_lottery <- h1b_policy %>%
  filter(!is.na(PW_year), !is.na(age)) %>%
  mutate(
    # Status Quo: Weights based on OFLC Level thresholds
    weight_status_quo = case_when(
      !eligible_status_quo ~ 0,  # Ineligible = 0 weight
      petition_annual_pay_clean >= Level4 ~ 4,
      petition_annual_pay_clean >= Level3 ~ 3,
      petition_annual_pay_clean >= Level2 ~ 2,
      petition_annual_pay_clean >= Level1 ~ 1,
      TRUE ~ 1  # Below Level1 gets 1 entry
    ),

    # 2021 Rule: Weights based on petition_percentile_combined thresholds
    weight_2021 = case_when(
      !eligible_2021 ~ 0,  # Ineligible = 0 weight
      petition_percentile_combined >= 90 ~ 4,
      petition_percentile_combined >= 72 ~ 3,
      petition_percentile_combined >= 53 ~ 2,
      petition_percentile_combined >= 35 ~ 1,
      TRUE ~ 0
    ),

    # Experience Benchmarking: Weights based on pw_p50/p62/p75/p90
    weight_eb = case_when(
      !eligible_eb ~ 0,  # Ineligible = 0 weight
      petition_annual_pay_clean >= pw_p90 ~ 4,
      petition_annual_pay_clean >= pw_p75 ~ 3,
      petition_annual_pay_clean >= pw_p62 ~ 2,
      petition_annual_pay_clean >= pw_p50 ~ 1,
      TRUE ~ 0
    )
  )

# Check weight distribution
weight_summary <- h1b_lottery %>%
  summarise(
    across(c(weight_status_quo, weight_2021, weight_eb),
           list(
             n_0 = ~sum(. == 0),
             n_1 = ~sum(. == 1),
             n_2 = ~sum(. == 2),
             n_3 = ~sum(. == 3),
             n_4 = ~sum(. == 4)
           ))
  )

cat("Weight distribution:\n")
print(weight_summary)

################################################################################
# ANALYSIS 16: Weighted Lottery - Median/Mean Salary by Year
################################################################################

cat("\n=== Analysis 16: Weighted Lottery Salaries by Year ===\n")

# Calculate weighted median and mean salaries by year for each policy
lottery_salary_stats <- h1b_lottery %>%
  pivot_longer(
    cols = c(weight_status_quo, weight_2021, weight_eb),
    names_to = "policy",
    values_to = "weight"
  ) %>%
  filter(weight > 0) %>%  # Only include eligible petitions
  mutate(
    policy = factor(case_when(
      policy == "weight_status_quo" ~ "Status Quo",
      policy == "weight_2021" ~ "2021 Rule",
      policy == "weight_eb" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "Experience Benchmarking"))
  ) %>%
  group_by(policy, PW_year) %>%
  summarise(
    # Weighted mean
    mean_salary = weighted.mean(petition_annual_pay_clean, weight, na.rm = TRUE),
    # Weighted median (approximate using weighted quantile)
    median_salary = matrixStats::weightedMedian(petition_annual_pay_clean, weight, na.rm = TRUE),
    .groups = "drop"
  )

print(lottery_salary_stats)

# Plot weighted median salary by year
p15 <- ggplot(lottery_salary_stats, aes(x = PW_year, y = median_salary, color = policy, group = policy)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  scale_color_manual(values = c(
    "Status Quo" = ifp_colors$rich_black,
    "2021 Rule" = ifp_colors$purple,
    "Experience Benchmarking" = ifp_colors$dark_blue
  )) +
  scale_y_continuous(labels = dollar_format(scale = 1/1000, suffix = "K")) +
  scale_x_continuous(breaks = 2021:2023) +
  labs(
    title = "Weighted Lottery Simulation: Median Salary by Year",
    subtitle = "Weighted by salary-based lottery entries under each policy",
    x = "Fiscal Year",
    y = "Median Salary",
    color = "Policy"
  ) +
  theme_ifp() +
  theme(legend.position = "bottom")

# Plot weighted mean salary by year
p16 <- ggplot(lottery_salary_stats, aes(x = PW_year, y = mean_salary, color = policy, group = policy)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  scale_color_manual(values = c(
    "Status Quo" = ifp_colors$rich_black,
    "2021 Rule" = ifp_colors$purple,
    "Experience Benchmarking" = ifp_colors$dark_blue
  )) +
  scale_y_continuous(labels = dollar_format(scale = 1/1000, suffix = "K")) +
  scale_x_continuous(breaks = 2021:2023) +
  labs(
    title = "Weighted Lottery Simulation: Mean Salary by Year",
    subtitle = "Weighted by salary-based lottery entries under each policy",
    x = "Fiscal Year",
    y = "Mean Salary",
    color = "Policy"
  ) +
  theme_ifp() +
  theme(legend.position = "bottom")

################################################################################
# ANALYSIS 17: Weighted Lottery - Age Distribution
################################################################################

cat("\n=== Analysis 17: Weighted Lottery Age Distribution ===\n")

# Create weighted age data for histogram
lottery_age_data <- h1b_lottery %>%
  pivot_longer(
    cols = c(weight_status_quo, weight_2021, weight_eb),
    names_to = "policy",
    values_to = "weight"
  ) %>%
  filter(weight > 0) %>%
  mutate(
    policy = factor(case_when(
      policy == "weight_status_quo" ~ "Status Quo",
      policy == "weight_2021" ~ "2021 Rule",
      policy == "weight_eb" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "Experience Benchmarking"))
  )

# Create weighted histogram by replicating rows based on weight
lottery_age_expanded <- lottery_age_data %>%
  uncount(weights = weight)

# Calculate age statistics from expanded data
lottery_age_stats <- lottery_age_expanded %>%
  group_by(policy) %>%
  summarise(
    median_age = median(age, na.rm = TRUE),
    p25_age = quantile(age, 0.25, na.rm = TRUE),
    p75_age = quantile(age, 0.75, na.rm = TRUE),
    .groups = "drop"
  )

print(lottery_age_stats)

p17 <- ggplot(lottery_age_expanded, aes(x = age)) +
  geom_histogram(binwidth = 2, fill = ifp_colors$dark_blue, color = "white") +
  geom_vline(data = lottery_age_stats, aes(xintercept = median_age),
             color = ifp_colors$orange, linewidth = 1, linetype = "solid") +
  geom_vline(data = lottery_age_stats, aes(xintercept = p25_age),
             color = ifp_colors$purple, linewidth = 0.8, linetype = "dashed") +
  geom_vline(data = lottery_age_stats, aes(xintercept = p75_age),
             color = ifp_colors$purple, linewidth = 0.8, linetype = "dashed") +
  geom_text(data = lottery_age_stats,
            aes(x = 55, y = Inf,
                label = sprintf("Median: %.0f\nP25: %.0f | P75: %.0f",
                               median_age, p25_age, p75_age)),
            vjust = 1.5, hjust = 1, size = 3, color = ifp_colors$rich_black) +
  facet_wrap(~policy, ncol = 1, scales = "free_y") +
  scale_x_continuous(limits = c(20, 60), breaks = seq(20, 60, 10)) +
  labs(
    title = "Weighted Lottery Simulation: Age Distribution",
    subtitle = "Weighted by salary-based lottery entries under each policy\nSolid line = median, dashed lines = 25th and 75th percentiles",
    x = "Age",
    y = "Count"
  ) +
  theme_ifp() +
  theme(strip.text = element_text(face = "bold", size = 10))

################################################################################
# ANALYSIS 18: Weighted Lottery - Median Wage Premium by Year
################################################################################

cat("\n=== Analysis 18: Weighted Lottery Median Wage Premium ===\n")

# Calculate weighted median wage premium ($ and %) by year for each policy
lottery_premium_stats <- h1b_lottery %>%
  pivot_longer(
    cols = c(weight_status_quo, weight_2021, weight_eb),
    names_to = "policy",
    values_to = "weight"
  ) %>%
  filter(weight > 0) %>%
  mutate(
    policy = factor(case_when(
      policy == "weight_status_quo" ~ "Status Quo",
      policy == "weight_2021" ~ "2021 Rule",
      policy == "weight_eb" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "Experience Benchmarking")),
    wage_premium_dollars = petition_annual_pay_clean - pw_p50,
    wage_premium_pct = ((petition_annual_pay_clean - pw_p50) / pw_p50) * 100
  ) %>%
  group_by(policy, PW_year) %>%
  summarise(
    median_premium_dollars = matrixStats::weightedMedian(wage_premium_dollars, weight, na.rm = TRUE),
    median_premium_pct = matrixStats::weightedMedian(wage_premium_pct, weight, na.rm = TRUE),
    .groups = "drop"
  )

print(lottery_premium_stats)

# Plot median wage premium in dollars by year
p18 <- ggplot(lottery_premium_stats, aes(x = PW_year, y = median_premium_dollars, color = policy, group = policy)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  scale_color_manual(values = c(
    "Status Quo" = ifp_colors$rich_black,
    "2021 Rule" = ifp_colors$purple,
    "Experience Benchmarking" = ifp_colors$dark_blue
  )) +
  scale_y_continuous(labels = dollar_format()) +
  scale_x_continuous(breaks = 2021:2023) +
  labs(
    title = "Weighted Lottery Simulation: Median Wage Premium by Year",
    subtitle = "Dollar amount above/below 50th percentile (weighted by lottery entries)",
    x = "Fiscal Year",
    y = "Median Wage Premium ($)",
    color = "Policy"
  ) +
  theme_ifp() +
  theme(legend.position = "bottom")

# Plot median wage premium in percent by year
p19 <- ggplot(lottery_premium_stats, aes(x = PW_year, y = median_premium_pct, color = policy, group = policy)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 3) +
  scale_color_manual(values = c(
    "Status Quo" = ifp_colors$rich_black,
    "2021 Rule" = ifp_colors$purple,
    "Experience Benchmarking" = ifp_colors$dark_blue
  )) +
  scale_y_continuous(labels = label_percent(scale = 1)) +
  scale_x_continuous(breaks = 2021:2023) +
  labs(
    title = "Weighted Lottery Simulation: Median Wage Premium by Year",
    subtitle = "Percent above/below 50th percentile (weighted by lottery entries)",
    x = "Fiscal Year",
    y = "Median Wage Premium (%)",
    color = "Policy"
  ) +
  theme_ifp() +
  theme(legend.position = "bottom")

################################################################################
# Export PDF
################################################################################

cat("\n=== Exporting PDF ===\n")

pdf("output/analysis/economic_analysis.pdf", width = 11, height = 8.5)

# Page 1: Overall stats
print(p1)

# Page 2: Scatterplot
print(p2)

# Page 3: Underpayment by age cohort (20-29, 30-39, 40-49, 50-59)
print(p3)

# Page 4: Underpayment by 5-year age group
print(p4)

# Page 5: Premium by 5-year age group
print(p5)

# Page 6: Policy comparison bar chart
print(p6)

# Page 7: Policy comparison table
print(p7)

# Page 8: Median underpayment ($) among underpaid by policy
print(p8)

# Page 9: Median underpayment (%) among underpaid by policy
print(p9)

# Page 10: Median wage premium ($) among eligible by policy
print(p10)

# Page 11: Median wage premium (%) among eligible by policy
print(p11)

# Page 12: Median salary by year and policy
print(p12)

# Page 13: Mean salary by year and policy
print(p13)

# Page 14: Age distribution by policy
print(p14)

# Page 15: Weighted lottery - median salary by year
print(p15)

# Page 16: Weighted lottery - mean salary by year
print(p16)

# Page 17: Weighted lottery - age distribution
print(p17)

# Page 18: Weighted lottery - median wage premium ($) by year
print(p18)

# Page 19: Weighted lottery - median wage premium (%) by year
print(p19)

dev.off()

cat("\n=== Analysis Complete ===\n")
cat("Output saved to: output/analysis/economic_analysis.pdf\n")
cat("Total pages: 19\n")
