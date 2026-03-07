################################################################################
# Script 08: Economic Analysis of H-1B Prevailing Wage Policies
#
# PURPOSE:
# This script analyzes different H-1B prevailing wage policy proposals by
# comparing underpayment rates and wage distributions across policy scenarios.
#
# POLICY SCENARIOS:
# 1. STATUS QUO: Current OFLC wage levels (all petitions eligible)
# 2. 2021 RULE: DOL's proposed percentile thresholds by wage level
#    - Level I: 35th percentile | Level II: 53rd percentile
#    - Level III: 72nd percentile | Level IV: 90th percentile
# 3. EXPERIENCE BENCHMARKING: Age-adjusted prevailing wage
#    - Workers must be paid >= pw_p50 (50th percentile for their age/education)
#
# KEY METRICS:
# - Underpaid: Workers paid less than pw_p50 (similarly-qualified Americans)
# - Wage Premium: Percentage above/below pw_p50
# - False Positives: Workers with positive wage premium but excluded by policy
# - False Negatives: Underpaid workers still eligible under policy
#
# Input:  data/processed/h1b_with_lifetime_earnings.csv
# Output: output/analysis/economic_analysis.pdf
#
# Author: Institute for Progress
# Date: March 2026
################################################################################

# Load required packages
library(tidyverse)
library(scales)
library(ggplot2)
library(gridExtra)

################################################################################
# IFP BRAND COLORS AND STYLING
################################################################################

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
  dark_blue = "#3368ce"
)

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

# Load data
cat("Loading H-1B petition data...\n")
h1b <- read_csv("data/processed/h1b_with_lifetime_earnings.csv",
                show_col_types = FALSE)
cat(sprintf("Loaded %s petitions\n", format(nrow(h1b), big.mark = ",")))

# Create output directory
dir.create("output/analysis", showWarnings = FALSE, recursive = TRUE)

################################################################################
# DATA PREPARATION
################################################################################

cat("\nPreparing data for analysis...\n")

h1b_valid <- h1b %>%
  filter(
    !is.na(petition_annual_pay_clean),
    !is.na(pw_p50),
    petition_annual_pay_clean > 0,
    pw_p50 > 0
  )

cat(sprintf("Valid petitions for analysis: %s\n", format(nrow(h1b_valid), big.mark = ",")))

# Filter to working age population (20-59)
h1b_policy <- h1b_valid %>%
  filter(
    !is.na(age),
    age >= 20,
    age <= 59
  ) %>%
  mutate(
    # Calculate wage premium
    wage_premium_pct = ((petition_annual_pay_clean - pw_p50) / pw_p50) * 100,
    wage_premium_dollars = petition_annual_pay_clean - pw_p50,

    # Age groupings
    age_cohort = case_when(
      age >= 20 & age < 30 ~ "20-29",
      age >= 30 & age < 40 ~ "30-39",
      age >= 40 & age < 50 ~ "40-49",
      age >= 50 & age < 60 ~ "50-59",
      TRUE ~ NA_character_
    ),
    age_group_5yr = case_when(
      age >= 20 & age < 25 ~ "20-24",
      age >= 25 & age < 30 ~ "25-29",
      age >= 30 & age < 35 ~ "30-34",
      age >= 35 & age < 40 ~ "35-39",
      age >= 40 & age < 45 ~ "40-44",
      age >= 45 & age < 50 ~ "45-49",
      age >= 50 & age < 55 ~ "50-54",
      age >= 55 & age < 60 ~ "55-59",
      TRUE ~ NA_character_
    ),

    # Policy eligibility flags
    eligible_status_quo = TRUE,  # Everyone eligible under status quo

    # 2021 Rule eligibility
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

    # 50th Percentile Minimum eligibility
    eligible_p50 = !is.na(petition_percentile_combined) & petition_percentile_combined >= 50,

    # Experience Benchmarking eligibility
    eligible_eb = petition_annual_pay_clean >= pw_p50
  )

################################################################################
# ANALYSIS 1: Scatterplot - Salary vs Wage Premium (2021 Rule Eligibility)
################################################################################

cat("\n=== Analysis 1: Salary vs Wage Premium (2021 Rule Eligibility) ===\n")

# Add eligibility labels for plotting
h1b_with_2021_eligibility <- h1b_policy %>%
  mutate(
    eligibility_2021 = if_else(eligible_2021, "Eligible under 2021 Rule", "Ineligible under 2021 Rule")
  )

p1 <- ggplot(h1b_with_2021_eligibility, aes(x = petition_annual_pay_clean, y = wage_premium_pct, color = eligibility_2021)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black, linewidth = 0.5) +
  geom_point(alpha = 0.4, size = 0.5) +
  scale_color_manual(
    values = c("Eligible under 2021 Rule" = ifp_colors$green,
               "Ineligible under 2021 Rule" = ifp_colors$red),
    name = "2021 Rule Status"
  ) +
  scale_x_continuous(labels = dollar_format(scale = 1/1000, suffix = "K"),
                     limits = c(0, 250000)) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     limits = c(-100, 200)) +
  labs(
    title = "Eligible Population: Salary vs Wage Premium by 2021 Rule Eligibility",
    subtitle = "Green = eligible under 2021 Rule | Red = ineligible under 2021 Rule",
    x = "Annual Salary",
    y = "Wage Premium (%)"
  ) +
  theme_ifp() +
  theme(legend.position = "bottom") +
  guides(color = guide_legend(override.aes = list(size = 4, alpha = 1)))

################################################################################
# ANALYSIS 2: Underpayment Rates by Age Cohort
################################################################################

cat("\n=== Analysis 2: Underpayment Rates by Age Cohort ===\n")

underpayment_by_cohort <- h1b_policy %>%
  filter(!is.na(age_cohort)) %>%
  group_by(age_cohort) %>%
  summarise(
    n_petitions = n(),
    n_underpaid = sum(petition_annual_pay_clean < pw_p50, na.rm = TRUE),
    pct_underpaid = (n_underpaid / n_petitions) * 100,
    .groups = "drop"
  )

print(underpayment_by_cohort)

p2 <- ggplot(underpayment_by_cohort, aes(x = age_cohort, y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     limits = c(0, max(underpayment_by_cohort$pct_underpaid) * 1.1)) +
  labs(
    title = "Underpayment Rate by Age Cohort",
    subtitle = "Share of workers paid below age-adjusted prevailing wage (pw_p50)",
    x = "Age Cohort",
    y = "Underpayment Rate (%)"
  ) +
  theme_ifp()

################################################################################
# ANALYSIS 3: Median Wage Premium by 5-Year Age Group
################################################################################

cat("\n=== Analysis 3: Median Wage Premium by 5-Year Age Group ===\n")

premium_by_age <- h1b_policy %>%
  filter(!is.na(age_group_5yr)) %>%
  group_by(age_group_5yr) %>%
  summarise(
    n_petitions = n(),
    median_premium = median(wage_premium_pct, na.rm = TRUE),
    mean_premium = mean(wage_premium_pct, na.rm = TRUE),
    .groups = "drop"
  )

print(premium_by_age)

p3 <- ggplot(premium_by_age, aes(x = age_group_5yr, y = median_premium)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black, linewidth = 0.8) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", median_premium),
                vjust = ifelse(median_premium >= 0, -0.5, 1.5)),
            size = 3.5, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1)) +
  labs(
    title = "Median Wage Premium by 5-Year Age Group",
    subtitle = "Percent above/below what similarly-qualified Americans earn",
    x = "Age Group",
    y = "Median Wage Premium (%)"
  ) +
  theme_ifp()

################################################################################
# ANALYSIS 4: Policy Comparison - Underpayment Rates
################################################################################

cat("\n=== Analysis 4: Policy Comparison ===\n")

policy_stats <- data.frame(
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
      sum(h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE),
      sum(h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE),
      sum(h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE),
      0  # Experience Benchmarking has zero underpayment by definition
    ),
    pct_underpaid = (n_underpaid / n_eligible) * 100,
    pct_eligible = (n_eligible / nrow(h1b_policy)) * 100
  )

print(policy_stats)

p4 <- ggplot(policy_stats, aes(x = policy, y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     limits = c(0, max(policy_stats$pct_underpaid) * 1.1)) +
  labs(
    title = "Eligible Population: Underpayment Rates by Policy",
    subtitle = "Share of eligible workers paid below age-adjusted prevailing wage",
    x = NULL,
    y = "Underpayment Rate (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 5: Policy Comparison Table (False Positives/Negatives)
################################################################################

cat("\n=== Analysis 5: Policy Comparison Table ===\n")

total_n <- nrow(h1b_policy)
total_underpaid <- sum(h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE)
total_positive_premium <- sum(h1b_policy$petition_annual_pay_clean >= h1b_policy$pw_p50, na.rm = TRUE)

cat(sprintf("Total petitions: %s\n", format(total_n, big.mark = ",")))
cat(sprintf("Total underpaid (< pw_p50): %s\n", format(total_underpaid, big.mark = ",")))
cat(sprintf("Total positive premium (>= pw_p50): %s\n", format(total_positive_premium, big.mark = ",")))

policy_table <- data.frame(
  Policy = factor(c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"),
                  levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking")),

  ineligible_n = c(
    sum(!h1b_policy$eligible_status_quo, na.rm = TRUE),
    sum(!h1b_policy$eligible_2021, na.rm = TRUE),
    sum(!h1b_policy$eligible_p50, na.rm = TRUE),
    sum(!h1b_policy$eligible_eb, na.rm = TRUE)
  ),

  eligible_underpaid_n = c(
    sum(h1b_policy$eligible_status_quo & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE),
    sum(h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE),
    sum(h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE),
    sum(h1b_policy$eligible_eb & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE)
  ),

  ineligible_positive_n = c(
    sum(!h1b_policy$eligible_status_quo & h1b_policy$petition_annual_pay_clean >= h1b_policy$pw_p50, na.rm = TRUE),
    sum(!h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean >= h1b_policy$pw_p50, na.rm = TRUE),
    sum(!h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean >= h1b_policy$pw_p50, na.rm = TRUE),
    sum(!h1b_policy$eligible_eb & h1b_policy$petition_annual_pay_clean >= h1b_policy$pw_p50, na.rm = TRUE)
  )
) %>%
  mutate(
    true_positive_n = ineligible_n - ineligible_positive_n,
    true_negative_n = total_positive_premium - ineligible_positive_n,
    accuracy = ((true_positive_n + true_negative_n) / total_n) * 100,

    `% Ineligible\n(Fail to Meet\nPolicy Threshold)` = sprintf("%.1f%%", (ineligible_n / total_n) * 100),
    `% False Negatives\n(Share of underpaid workers\nwho are still eligible)` = sprintf("%.1f%%", (eligible_underpaid_n / total_underpaid) * 100),
    `% False Positives\n(Share of positive premium\nworkers who are ineligible)` = sprintf("%.1f%%", (ineligible_positive_n / total_positive_premium) * 100),
    `Accuracy Rate\n(Correctly Classified)` = sprintf("%.1f%%", accuracy)
  ) %>%
  select(Policy, `% Ineligible\n(Fail to Meet\nPolicy Threshold)`,
         `% False Negatives\n(Share of underpaid workers\nwho are still eligible)`,
         `% False Positives\n(Share of positive premium\nworkers who are ineligible)`,
         `Accuracy Rate\n(Correctly Classified)`)

print(policy_table)

p5 <- ggplot() +
  annotation_custom(gridExtra::tableGrob(policy_table,
                                        rows = NULL,
                                        theme = gridExtra::ttheme_minimal(
                                          base_size = 10,
                                          core = list(fg_params = list(hjust = 0, x = 0.05)),
                                          colhead = list(fg_params = list(fontface = "bold"))
                                        ))) +
  theme_void() +
  labs(title = "Policy Comparison: False Positives and False Negatives",
       subtitle = "False Negatives: of all underpaid workers | False Positives: of all positive premium workers") +
  theme_ifp()

################################################################################
# ANALYSIS 6: Median Underpayment Among Underpaid Workers
################################################################################

cat("\n=== Analysis 6: Median Underpayment ($) by Policy ===\n")

median_underpay_dollars <- data.frame(
  Policy = factor(c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"),
                  levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking")),
  median_underpay = c(
    median(h1b_policy$petition_annual_pay_clean[h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
           h1b_policy$pw_p50[h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50], na.rm = TRUE),
    median(h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
           h1b_policy$pw_p50[h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50], na.rm = TRUE),
    median(h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
           h1b_policy$pw_p50[h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50], na.rm = TRUE),
    0
  )
)

print(median_underpay_dollars)

p6 <- ggplot(median_underpay_dollars, aes(x = Policy, y = median_underpay)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("$%s", format(round(median_underpay), big.mark = ","))),
            vjust = 1.5, size = 4, color = "white") +
  scale_y_continuous(labels = label_dollar(), limits = c(min(median_underpay_dollars$median_underpay) * 1.1, 0)) +
  labs(
    title = "Eligible Population: Median Underpayment Among Underpaid Workers",
    subtitle = "Dollars below age-adjusted prevailing wage (negative = underpaid)",
    x = NULL,
    y = "Median Underpayment ($)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 7: Median Underpayment (%) Among Underpaid Workers
################################################################################

cat("\n=== Analysis 7: Median Underpayment (%) by Policy ===\n")

# Calculate median underpayment in percentage terms for underpaid workers under each policy
median_underpay_pct <- data.frame(
  Policy = factor(c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"),
                  levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking")),

  median_underpay_pct = c(
    # Status Quo: all underpaid workers
    median(((h1b_policy$pw_p50[h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
             h1b_policy$petition_annual_pay_clean[h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) /
            h1b_policy$pw_p50[h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) * 100, na.rm = TRUE),

    # 2021 Rule: eligible and underpaid
    median(((h1b_policy$pw_p50[h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
             h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) /
            h1b_policy$pw_p50[h1b_policy$eligible_2021 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) * 100, na.rm = TRUE),

    # 50th Percentile: eligible and underpaid
    median(((h1b_policy$pw_p50[h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50] -
             h1b_policy$petition_annual_pay_clean[h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) /
            h1b_policy$pw_p50[h1b_policy$eligible_p50 & h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50]) * 100, na.rm = TRUE),

    # Experience Benchmarking: no underpaid workers by definition
    0
  )
)

print(median_underpay_pct)

p7 <- ggplot(median_underpay_pct, aes(x = Policy, y = median_underpay_pct)) +
  geom_col(fill = ifp_colors$red) +
  geom_text(aes(label = sprintf("%.1f%%", median_underpay_pct)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Eligible Population: Median Underpayment Among Underpaid Workers",
    subtitle = "Percent below what similarly-qualified Americans earn",
    x = NULL,
    y = "Median Underpayment (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 8: Median Salary Comparison (Status Quo vs Experience Benchmarking)
################################################################################

cat("\n=== Analysis 8: Median Salary Comparison by Year (Status Quo vs EB) ===\n")

median_comparison <- h1b_policy %>%
  filter(!is.na(PW_year)) %>%
  group_by(PW_year) %>%
  summarise(
    status_quo = median(petition_annual_pay_clean[eligible_status_quo], na.rm = TRUE),
    experience_benchmarking = median(petition_annual_pay_clean[eligible_eb], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    difference = experience_benchmarking - status_quo,
    pct_increase = (difference / status_quo) * 100
  ) %>%
  rename(Year = PW_year,
         `Status Quo` = status_quo,
         `Experience Benchmarking` = experience_benchmarking,
         `Difference` = difference,
         `% Increase` = pct_increase)

print(median_comparison)

p8 <- gridExtra::tableGrob(
  median_comparison %>%
    mutate(
      Year = sprintf("FY %d", Year + 1),
      `Status Quo` = sprintf("$%s", format(round(`Status Quo`), big.mark = ",")),
      `Experience Benchmarking` = sprintf("$%s", format(round(`Experience Benchmarking`), big.mark = ",")),
      `Difference` = sprintf("+$%s", format(round(`Difference`), big.mark = ",")),
      `% Increase` = sprintf("+%.1f%%", `% Increase`)
    ),
  rows = NULL,
  theme = gridExtra::ttheme_minimal(
    core = list(fg_params = list(hjust = 1, x = 0.95, fontsize = 11)),
    colhead = list(fg_params = list(fontsize = 12, fontface = "bold"))
  )
)

################################################################################
# PDF EXPORT
################################################################################

cat("\n=== Exporting PDF ===\n")

pdf("output/analysis/economic_analysis.pdf", width = 11, height = 8.5)

# Page 1: Scatterplot (2021 Rule eligibility)
print(p1)

# Page 2: Underpayment by age cohort
print(p2)

# Page 3: Median wage premium by 5-year age group
print(p3)

# Page 4: Policy comparison (underpayment rates)
print(p4)

# Page 5: Policy comparison table
print(p5)

# Page 6: Median underpayment among underpaid ($)
print(p6)

# Page 7: Median underpayment among underpaid (%)
print(p7)

# Page 8: Median salary comparison table
grid::grid.newpage()
grid::grid.draw(p8)
title_grob <- grid::textGrob("Median H-1B Salary by Prevailing Wage Proposal",
                             y = 0.95, gp = grid::gpar(fontsize = 16, fontface = "bold"))
grid::grid.draw(title_grob)

dev.off()

cat("\n=== Analysis Complete ===\n")
cat("Output saved to: output/analysis/economic_analysis.pdf\n")
cat("Total pages: 8\n\n")
cat("Page 1: Salary vs Wage Premium (2021 Rule Eligibility)\n")
cat("Page 2: Underpayment by Age Cohort\n")
cat("Page 3: Median Wage Premium by 5-Year Age Group\n")
cat("Page 4: Policy Comparison - Underpayment Rates\n")
cat("Page 5: Policy Comparison Table (False Positives/Negatives)\n")
cat("Page 6: Median Underpayment Among Underpaid Workers ($)\n")
cat("Page 7: Median Underpayment Among Underpaid Workers (%)\n")
cat("Page 8: Median Salary Comparison Table (Status Quo vs Experience Benchmarking)\n")
