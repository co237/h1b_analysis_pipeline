################################################################################
# Script 08: Economic Analysis of H-1B Prevailing Wage Policies (FULL VERSION)
#
# PURPOSE & METHODOLOGY:
# This script generates a comprehensive 59-page PDF analyzing different H-1B
# prevailing wage policy proposals. It compares four policy scenarios:
#
# 1. STATUS QUO: Current OFLC wage levels (Level I-IV)
#    - All petitions with valid prevailing wage data are eligible
#    - No minimum wage threshold beyond OFLC requirements
#
# 2. 2021 RULE: DOL's 2021 proposed percentile-based thresholds
#    - Level I requires 35th percentile
#    - Level II requires 53rd percentile
#    - Level III requires 72nd percentile
#    - Level IV requires 90th percentile
#    - Uses petition_percentile_combined for eligibility
#
# 3. 50TH PERCENTILE MINIMUM: Uniform floor across all wage levels
#    - All petitions must meet 50th percentile threshold
#    - Uses petition_percentile_combined >= 50 for eligibility
#
# 4. EXPERIENCE BENCHMARKING: Age-adjusted prevailing wage (IFP's proposal)
#    - Workers must be paid >= pw_p50 (50th percentile for their age/education)
#    - Automatically accounts for worker experience via age
#    - Zero underpayment by definition (eligible only if meeting threshold)
#
# ANALYSIS STRUCTURE:
# - Pages 1-20: Eligible Population analyses (who can apply under each policy)
# - Pages 21-28: Weighted Lottery simulation (who gets selected under weighted lottery)
# - Pages 29-34: Industry and Occupation composition analyses
# - Pages 35-40: Lifetime Earnings analyses (using NPV multipliers from Script 09)
# - Pages 41-44: Policy comparison analyses (underpayment by industry/occupation)
# - Pages 45-59: Firm Type and Education Level analyses (new for launch paper)
#
# KEY CONCEPTS:
# - Eligible Population: Workers who meet the policy's wage threshold
# - Underpaid: Workers paid less than pw_p50 (similarly-qualified Americans)
# - Wage Premium: % above/below pw_p50
# - Weighted Lottery: Simulation where higher-paid workers get more lottery entries
#   (1 entry at minimum, up to 4 entries at highest thresholds)
#
# Input:  data/processed/h1b_with_lifetime_earnings.csv
#         (Output from Script 07 - includes age, pw_p50, lifetime earnings)
# Output: output/analysis/economic_analysis.pdf (59 pages)
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

################################################################################
# IFP BRAND COLORS AND STYLING
#
# Institute for Progress uses a specific color palette for all visualizations.
# These colors are defined in IFP_style2024.css and ensure brand consistency.
#
# PRIMARY COLORS:
# - off_white (#fcfbeb): Background color for all plots
# - rich_black (#373737): Default text and axis color
# - purple (#b17ada): Primary accent color (often used for policy proposals)
# - orange (#ff9762): Secondary accent color (highlights, medians)
#
# CATEGORY COLORS (by policy area):
# - dark_blue (#3368ce): Immigration policy (used extensively in this analysis)
# - green (#39d794): Biotechnology
# - red (#ff6565): Metascience (also used for "underpaid" indicators)
# - light_blue (#41c4fc): Emerging Technology
# - yellow (#fbdb36): Energy
# - pink (#ff9ee3): Infrastructure
#
# USAGE NOTES:
# - Always use off_white backgrounds (never pure white)
# - Use rich_black for text (better contrast than pure black)
# - Limit to 2-3 colors per chart for clarity
# - Use red for negative/underpaid indicators, green for positive/overpaid
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
  dark_blue = "#3368ce"  # Immigration category (primary color for this analysis)
)

################################################################################
# IFP THEME FUNCTION
#
# This function creates a consistent ggplot2 theme for all visualizations.
# It ensures:
# - IFP brand colors (off_white background, rich_black text)
# - Appropriate text sizes for PDF output (11x8.5 inches)
# - Clean, minimal gridlines (major only, no minor gridlines)
# - Consistent title/subtitle/axis formatting
#
# USAGE: Add "+ theme_ifp()" to every ggplot object in this script
#
# CUSTOMIZATION: Individual plots can override specific theme elements after
# applying theme_ifp(), e.g.:
#   ggplot(...) + theme_ifp() + theme(axis.text.x = element_text(angle = 45))
################################################################################

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
cat("Loading H-1B petition data with lifetime earnings...\n")
h1b <- read_csv("data/processed/h1b_with_lifetime_earnings.csv",
                show_col_types = FALSE)

cat(sprintf("Loaded %s petitions\n", format(nrow(h1b), big.mark = ",")))

# Create output directory ------------------------------------------------------
dir.create("output/analysis", showWarnings = FALSE, recursive = TRUE)

################################################################################
# DATA PREPARATION AND FILTERING
#
# We start with the output from Script 07 (h1b_with_lifetime_earnings.csv) which
# includes:
# - petition_annual_pay_clean: The salary offered to the H-1B worker
# - pw_p50: 50th percentile prevailing wage for workers of similar age/education
# - age: Worker age (imputed from education in Script 04)
# - lifetime_earnings_3pct/7pct: NPV of expected lifetime earnings
# - petition_percentile_combined: Worker's salary percentile within their occupation
# - OFLC wage levels (Level1_full, Level2_full, Level3_full, Level4_full)
#
# FILTERING LOGIC:
# We filter to "valid" petitions that have:
# 1. Non-missing salary (petition_annual_pay_clean)
# 2. Non-missing prevailing wage benchmark (pw_p50)
# 3. Positive values for both (excludes data errors)
# 4. Valid age group (20-59 years)
#
# This ensures we can calculate wage premiums and policy eligibility for all
# petitions in our analysis dataset.
#
# KEY DERIVED VARIABLES:
# - wage_premium_pct: How much above/below pw_p50 (in percent)
#   Example: If paid $100k and pw_p50 is $90k, premium = +11.1%
# - underpaid: Binary indicator (TRUE if paid less than similarly-qualified Americans)
# - age_group_5yr: 5-year age bins for age-stratified analyses
################################################################################

cat("\nPreparing data for analysis...\n")

# Filter to valid petitions with required fields
h1b_valid <- h1b %>%
  filter(
    !is.na(petition_annual_pay_clean),  # Must have salary data
    !is.na(pw_p50),                     # Must have age-adjusted prevailing wage
    petition_annual_pay_clean > 0,      # Exclude zero/negative salaries (data errors)
    pw_p50 > 0                          # Exclude zero/negative prevailing wages
  )

cat(sprintf("Valid petitions for analysis: %s\n",
            format(nrow(h1b_valid), big.mark = ",")))

# Calculate wage premium and create age groups
h1b_valid <- h1b_valid %>%
  mutate(
    # Wage premium: percentage above/below what similarly-qualified Americans earn
    # Positive = paid more than benchmark, Negative = paid less
    wage_premium_pct = ((petition_annual_pay_clean - pw_p50) / pw_p50) * 100,

    # Underpaid indicator: TRUE if paid less than pw_p50
    # This is the key metric for assessing wage displacement concerns
    underpaid = petition_annual_pay_clean < pw_p50,

    # 5-year age groups for age-stratified analyses
    # We use 5-year bins (20-24, 25-29, etc.) to balance granularity and sample size
    age_group_5yr = case_when(
      age >= 20 & age <= 24 ~ "20-24",
      age >= 25 & age <= 29 ~ "25-29",
      age >= 30 & age <= 34 ~ "30-34",
      age >= 35 & age <= 39 ~ "35-39",
      age >= 40 & age <= 44 ~ "40-44",
      age >= 45 & age <= 49 ~ "45-49",
      age >= 50 & age <= 54 ~ "50-54",
      age >= 55 & age <= 59 ~ "55-59",
      TRUE ~ NA_character_   # Ages outside 20-59 (should be rare after Script 04)
    )
  ) %>%
  filter(!is.na(age_group_5yr))  # Remove any remaining invalid ages

################################################################################
# ANALYSIS 1: Overall Underpayment Share and Median Wage Premium
#
# This opening page provides the key headline statistics:
# - Total number of H-1B petitions with valid experience benchmarking data
# - Percentage paid less than similarly-qualified Americans (underpayment rate)
# - Median wage premium (typical % above/below benchmark)
#
# INTERPRETATION:
# If underpayment rate is high (e.g., 30%+), this suggests significant wage
# displacement concerns. If median premium is negative, the typical H-1B worker
# is paid less than comparable Americans.
#
# OUTPUT: Text-based summary page for PDF (page 1)
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
  annotate("text", x = 0.5, y = 0.85,
           label = "H-1B Petitions with Valid Experience Benchmarking Wages",
           size = 7, fontface = "bold", color = ifp_colors$rich_black) +
  annotate("text", x = 0.5, y = 0.75,
           label = sprintf("(FY 2021-2023, n = %s)", format(overall_stats$total_petitions, big.mark = ",")),
           size = 5, color = ifp_colors$rich_black) +
  annotate("text", x = 0.5, y = 0.55,
           label = sprintf("%.1f%%", overall_stats$pct_underpaid),
           size = 24, fontface = "bold", color = ifp_colors$dark_blue) +
  annotate("text", x = 0.5, y = 0.35,
           label = "of petitions are paid below what\nsimilarly-qualified Americans earn",
           size = 6, color = ifp_colors$rich_black) +
  annotate("text", x = 0.5, y = 0.15,
           label = sprintf("Median wage premium vs. similarly-qualified: %.1f%%", overall_stats$median_premium),
           size = 5, color = ifp_colors$rich_black, fontface = "italic") +
  xlim(0, 1) + ylim(0, 1) +
  theme_void() +
  theme(plot.background = element_rect(fill = ifp_colors$off_white, color = NA))

################################################################################
# ANALYSIS 2: Scatterplot - Salary vs Wage Premium
################################################################################

cat("\n=== Analysis 2: Salary vs Wage Premium ===\n")

# Use full dataset (no sampling)
p2 <- ggplot(h1b_valid, aes(x = petition_annual_pay_clean, y = wage_premium_pct)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black, linewidth = 0.5) +
  geom_point(alpha = 0.3, color = ifp_colors$dark_blue, size = 0.5) +
  geom_smooth(method = "lm", formula = y ~ x,
              color = ifp_colors$orange, se = FALSE, linewidth = 1.5) +
  scale_x_continuous(labels = dollar_format(scale = 1/1000, suffix = "K"),
                     limits = c(0, 250000)) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     limits = c(-100, 200)) +
  labs(
    title = "Eligible Population: Salary vs Wage Premium",
    subtitle = "Relative to what similarly-qualified Americans earn (experience-adjusted prevailing wage)",
    x = "Annual Salary",
    y = "Wage Premium (%)"
  ) +
  theme_ifp()

################################################################################
# ANALYSIS 2A: Scatterplot - Salary vs Wage Premium (Colored by 2021 Rule Eligibility)
#
# This visualization shows the same data as Analysis 2, but colors points based
# on whether they would be eligible under the 2021 Rule policy.
#
# COLOR CODING:
# - GREEN: Eligible under 2021 Rule (meets percentile threshold for their wage level)
# - RED: Ineligible under 2021 Rule (below percentile threshold)
#
# INTERPRETATION:
# This reveals the spatial distribution of who gets excluded by the 2021 Rule.
# If red dots cluster in certain salary/premium ranges, it shows which workers
# are systematically excluded by the policy.
################################################################################

cat("\n=== Analysis 2A: Salary vs Wage Premium (2021 Rule Eligibility) ===\n")

# Calculate 2021 Rule eligibility for full dataset
# (This is the same logic used later in Analysis 6)
h1b_with_2021_eligibility <- h1b_valid %>%
  mutate(
    # Calculate 2021 Rule threshold based on wage level
    threshold_2021 = case_when(
      PW_WAGE_LEVEL == "I" ~ 35,   # Entry level
      PW_WAGE_LEVEL == "II" ~ 53,  # Qualified
      PW_WAGE_LEVEL == "III" ~ 72, # Experienced
      PW_WAGE_LEVEL == "IV" ~ 90,  # Fully competent
      TRUE ~ NA_real_
    ),
    # Determine eligibility
    eligible_2021 = !is.na(threshold_2021) &
                    !is.na(petition_percentile_combined) &
                    petition_percentile_combined >= threshold_2021,
    # Create label for plotting
    eligibility_2021 = if_else(eligible_2021, "Eligible under 2021 Rule", "Ineligible under 2021 Rule")
  )

p2a <- ggplot(h1b_with_2021_eligibility, aes(x = petition_annual_pay_clean, y = wage_premium_pct, color = eligibility_2021)) +
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
    title = "Eligible Population: Underpayment Rates by Age Cohort",
    subtitle = "Percentage paid less than similarly-qualified Americans",
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
    title = "Eligible Population: Underpayment by 5-Year Age Group",
    subtitle = "Percentage paid less than similarly-qualified Americans",
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
    title = "Eligible Population: Median Wage Premium by 5-Year Age Group",
    subtitle = "Percent above/below what similarly-qualified Americans earn",
    x = "Age Group",
    y = "Median Premium (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 0))

################################################################################
# ANALYSIS 6: Policy Comparison - Underpayment Rates
#
# This is the CRITICAL section that defines eligibility under each policy proposal.
# Understanding these definitions is essential for interpreting all subsequent analyses.
#
# FOUR POLICY SCENARIOS:
#
# 1. STATUS QUO (eligible_status_quo):
#    - Current OFLC rules: All petitions with valid prevailing wage data are eligible
#    - No additional salary thresholds beyond existing OFLC Level I-IV requirements
#    - RESULT: Nearly everyone in h1b_valid is eligible
#
# 2. 2021 RULE (eligible_2021):
#    - DOL's 2021 proposed percentile-based thresholds tied to OFLC wage levels
#    - Uses petition_percentile_combined (worker's salary percentile in their occupation)
#    - Thresholds by wage level:
#      * Level I (entry-level) → must be at 35th percentile
#      * Level II (qualified) → must be at 53rd percentile
#      * Level III (experienced) → must be at 72nd percentile
#      * Level IV (fully competent) → must be at 90th percentile
#    - RATIONALE: Higher skill levels should command higher relative wages
#    - ISSUE: Does NOT account for age/experience (young PhD can be underpaid at 35th percentile)
#
# 3. 50TH PERCENTILE MINIMUM (eligible_p50):
#    - Uniform floor: ALL workers must be at 50th percentile in their occupation
#    - Simpler than 2021 Rule (same threshold regardless of declared wage level)
#    - ISSUE: Still doesn't account for age/experience differences
#
# 4. EXPERIENCE BENCHMARKING (eligible_eb):
#    - IFP's proposal: Must meet pw_p50 (age-adjusted prevailing wage)
#    - Automatically accounts for experience via age
#    - Example: 25-year-old must earn what typical 25-year-old earns at 50th percentile
#    - RESULT: Zero underpayment by definition (only eligible if meeting threshold)
#
# KEY INSIGHT: The first three policies can have "eligible but underpaid" workers
# (they meet the policy threshold but are still paid less than similarly-qualified
# Americans). Experience Benchmarking eliminates this by using age-adjusted benchmarks.
#
# UNDERPAYMENT DEFINITION ACROSS ALL POLICIES:
# A worker is "underpaid" if petition_annual_pay_clean < pw_p50, regardless of
# which policy made them eligible. This allows apples-to-apples comparison of
# underpayment rates across policies.
################################################################################

cat("\n=== Analysis 6: Policy Comparison ===\n")

# Create policy eligibility indicators for all four scenarios
h1b_policy <- h1b_valid %>%
  mutate(
    # STATUS QUO: Current rules - all valid petitions are eligible
    eligible_status_quo = !is.na(pw_p50),
    underpaid_status_quo = petition_annual_pay_clean < pw_p50,

    # 2021 RULE: Percentile thresholds tied to OFLC wage levels
    # Calculate the required percentile threshold based on declared wage level
    threshold_2021 = case_when(
      PW_WAGE_LEVEL == "I" ~ 35,   # Entry level
      PW_WAGE_LEVEL == "II" ~ 53,  # Qualified
      PW_WAGE_LEVEL == "III" ~ 72, # Experienced
      PW_WAGE_LEVEL == "IV" ~ 90,  # Fully competent
      TRUE ~ NA_real_              # Missing or invalid wage level
    ),
    # Eligible if salary meets the threshold for declared wage level
    eligible_2021 = !is.na(threshold_2021) &
                    !is.na(petition_percentile_combined) &
                    petition_percentile_combined >= threshold_2021,
    # Can still be underpaid even if eligible (if below age-adjusted benchmark)
    underpaid_2021 = eligible_2021 & petition_annual_pay_clean < pw_p50,

    # 50TH PERCENTILE MINIMUM: Simple uniform floor
    # Must be at 50th percentile in occupation (no variation by wage level)
    eligible_p50 = !is.na(petition_percentile_combined) & petition_percentile_combined >= 50,
    # Can still be underpaid even if eligible (if below age-adjusted benchmark)
    underpaid_p50 = eligible_p50 & petition_annual_pay_clean < pw_p50,

    # EXPERIENCE BENCHMARKING: Must meet age-adjusted prevailing wage
    # Eligible only if salary >= pw_p50
    eligible_eb = petition_annual_pay_clean >= pw_p50,
    # By definition, no one eligible under this policy is underpaid
    underpaid_eb = FALSE
  )

################################################################################
# FIRM TYPE CLASSIFICATION
#
# Classify firms into three categories for analysis:
# 1. IT Outsourcers: Large staffing/consulting firms identified by Bloomberg
# 2. H-1B Dependent: Firms with >15% H-1B workforce (from petition data)
# 3. Other: All other firms
#
# This classification enables analysis of differential underpayment patterns
# across firm types.
################################################################################

# List of large IT outsourcers using the H-1B program, as described by Bloomberg
outsourcer_list <- c(
  "Infosys Limited",
  "Cognizant Technology Solutions US Corp",
  "Accenture LLP",
  "Tech Mahindra Americas Inc",
  "Tata Consultancy Services Limited",
  "Wipro Limited",
  "Mindtree Limited",
  "Capgemini America, Inc.",
  "Deloitte Consulting LLP",
  "HCL America Inc",
  "IBM Corporation",
  "Ernst & Young U.S. LLP",
  "WIPRO LIMITED",
  "Tech Mahindra Americas Inc.",
  "IBM Corp",
  "Snowstack LLC",
  "Larsen & Toubro Infotech Limited",
  "ATOS SYNTEL INC",
  "MindTree Limited",
  "LTIMINDTREE LIMITED",
  "MARVELOUS TECHNOLOGIES INC",
  "EVIDEN USA, INC.",
  "PRIMITIVE PARTNERS LLC",
  "Datics Inc",
  "Objects Experts LLC",
  "B3R Technologies LLC",
  "CloudNine Tek LLC",
  "Valuepro, Inc",
  "Zenspace IT LLC",
  "AVALANCHE TECHNOLOGIES LLC",
  "TECHSUFFICE LLC",
  "Aclat, Inc."
)

# Add firm type classification to h1b_policy
h1b_policy <- h1b_policy %>%
  mutate(
    # IT Outsourcer flag
    is_it_outsourcer = petition_employer_name %in% outsourcer_list |
                       registration_employer_name %in% outsourcer_list,

    # H-1B Dependent flag (already in data)
    is_h1b_dependent = petition_employer_h1b_dependent == "Y",

    # Firm type classification (mutually exclusive, prioritizing IT outsourcer)
    firm_type = case_when(
      is_it_outsourcer ~ "IT Outsourcer",
      is_h1b_dependent ~ "H-1B Dependent",
      TRUE ~ "Other"
    ),

    firm_type = factor(firm_type,
                      levels = c("IT Outsourcer", "H-1B Dependent", "Other"))
  )

cat(sprintf("\nFirm type distribution:\n"))
cat(sprintf("  IT Outsourcers: %s (%.1f%%)\n",
            format(sum(h1b_policy$is_it_outsourcer, na.rm = TRUE), big.mark = ","),
            100 * mean(h1b_policy$is_it_outsourcer, na.rm = TRUE)))
cat(sprintf("  H-1B Dependent: %s (%.1f%%)\n",
            format(sum(h1b_policy$is_h1b_dependent, na.rm = TRUE), big.mark = ","),
            100 * mean(h1b_policy$is_h1b_dependent, na.rm = TRUE)))
cat(sprintf("  Other: %s (%.1f%%)\n",
            format(sum(h1b_policy$firm_type == "Other", na.rm = TRUE), big.mark = ","),
            100 * mean(h1b_policy$firm_type == "Other", na.rm = TRUE)))

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
    title = "Eligible Population: Underpayment Rates by Policy",
    subtitle = "Percentage of eligible workers paid less than similarly-qualified Americans",
    x = NULL,
    y = "Underpaid Among Eligible (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 7: Policy Comparison Table
#
# This table shows the trade-offs of each policy using three metrics:
#
# 1. % INELIGIBLE (False Exclusions):
#    - Share of all petitions that fail to meet the policy threshold
#    - Higher = more restrictive policy (excludes more applicants)
#    - Status Quo = 0% (everyone eligible)
#    - Experience Benchmarking ≈ 30% (excludes underpaid workers)
#
# 2. % FALSE NEGATIVES (Share of underpaid workers who are still eligible):
#    - Of all underpaid workers, what % still pass the policy test?
#    - These are workers paid less than Americans who slip through
#    - Higher = policy fails to catch underpayment
#    - Experience Benchmarking = 0% (by design, no underpaid workers are eligible)
#
# 3. % FALSE POSITIVES (Share of positive premium workers who are ineligible):
#    - Of all workers with positive wage premiums, what % are blocked?
#    - These are "good" employers mistakenly excluded
#    - Higher = policy unnecessarily restricts high-quality applications
#    - Status Quo = 0% (no one excluded)
#
# POLICY TRADE-OFF:
# More restrictive policies (like Experience Benchmarking) have:
# - HIGH % Ineligible (many excluded)
# - LOW % False Negatives (few underpaid workers slip through)
# - LOW % False Positives (few good employers blocked)
#
# Less restrictive policies (like Status Quo) have:
# - LOW % Ineligible (few excluded)
# - HIGH % False Negatives (many underpaid workers slip through)
# - LOW % False Positives (few good employers blocked)
#
# OUTPUT: Formatted table showing these three metrics for each policy
################################################################################

cat("\n=== Analysis 7: Policy Comparison Table ===\n")

# Calculate baseline totals for denominator calculations
total_n <- nrow(h1b_policy)  # Total petitions
total_underpaid <- sum(h1b_policy$petition_annual_pay_clean < h1b_policy$pw_p50, na.rm = TRUE)  # All underpaid
total_positive_premium <- sum(h1b_policy$petition_annual_pay_clean >= h1b_policy$pw_p50, na.rm = TRUE)  # All paying competitively

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
    # Calculate confusion matrix components
    # TP = correctly excluded underpaid workers (ineligible AND underpaid)
    true_positive_n = ineligible_n - ineligible_positive_n,
    # TN = correctly included fairly-paid workers (eligible AND fairly-paid)
    true_negative_n = total_positive_premium - ineligible_positive_n,
    # FN = incorrectly included underpaid workers (already calculated)
    false_negative_n = eligible_underpaid_n,
    # FP = incorrectly excluded fairly-paid workers (already calculated)
    false_positive_n = ineligible_positive_n,

    # Accuracy = (TP + TN) / Total
    accuracy = ((true_positive_n + true_negative_n) / total_n) * 100,

    # Format display columns
    `% Ineligible\n(Fail to Meet\nPolicy Threshold)` = sprintf("%.1f%%", (ineligible_n / total_n) * 100),
    `% False Negatives\n(Share of underpaid workers\nwho are still eligible)` = sprintf("%.1f%%", (eligible_underpaid_n / total_underpaid) * 100),
    `% False Positives\n(Share of positive premium\nworkers who are ineligible)` = sprintf("%.1f%%", (ineligible_positive_n / total_positive_premium) * 100),
    `Accuracy Rate\n(Correctly Classified)` = sprintf("%.1f%%", accuracy)
  ) %>%
  select(Policy, `% Ineligible\n(Fail to Meet\nPolicy Threshold)`,
         `% False Negatives\n(Share of underpaid workers\nwho are still eligible)`,
         `% False Positives\n(Share of positive premium\nworkers who are ineligible)`,
         `Accuracy Rate\n(Correctly Classified)`)

print(policy_table_data)

# Create table as a ggplot object for PDF with better styling
table_grob <- tableGrob(policy_table_data, rows = NULL,
                        theme = ttheme_minimal(
                          core = list(
                            fg_params = list(hjust = 0.5, x = 0.5, fontsize = 10),
                            bg_params = list(fill = ifp_colors$off_white)
                          ),
                          colhead = list(
                            fg_params = list(fontface = "bold", fontsize = 9, col = ifp_colors$off_white),
                            bg_params = list(fill = ifp_colors$dark_blue)
                          )
                        ))

p7 <- ggplot() +
  annotation_custom(table_grob) +
  labs(
    title = "Eligible Population: Policy Comparison Summary",
    subtitle = "All percentages are shares of their respective totals\n(% Ineligible: of all petitions | False Negatives: of all underpaid workers | False Positives: of all positive premium workers)"
  ) +
  theme_void() +
  theme(
    plot.title = element_text(size = 16, face = "bold", hjust = 0.5,
                              color = ifp_colors$rich_black, margin = margin(b = 5)),
    plot.subtitle = element_text(size = 9, hjust = 0.5,
                                 color = ifp_colors$rich_black, margin = margin(b = 15)),
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
    title = "Eligible Population: Median Underpayment Among Underpaid Workers",
    subtitle = "Dollar amount below what similarly-qualified Americans earn (negative values)",
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
    title = "Eligible Population: Median Underpayment Among Underpaid Workers",
    subtitle = "Percent below what similarly-qualified Americans earn (positive values)",
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
    title = "Eligible Population: Median Wage Premium Among Eligible Workers",
    subtitle = "Dollar amount above/below what similarly-qualified Americans earn",
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
    title = "Eligible Population: Median Wage Premium Among Eligible Workers",
    subtitle = "Percent above/below what similarly-qualified Americans earn",
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
    title = "Eligible Population: Median Salary by Year",
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
    title = "Eligible Population: Mean Salary by Year",
    subtitle = "Comparing policy proposals across fiscal years",
    x = "Fiscal Year",
    y = "Mean Salary",
    color = "Policy"
  ) +
  theme_ifp() +
  theme(legend.position = "bottom")

################################################################################
# ANALYSIS 13A: Median Salary Comparison (Status Quo vs Experience Benchmarking)
################################################################################

cat("\n=== Analysis 13A: Median Salary Comparison by Year (Status Quo vs EB) ===\n")

# Create comparison table for median salaries
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

# Create formatted table for display
p13a <- gridExtra::tableGrob(
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
# ANALYSIS 13B: Mean Salary Comparison (Status Quo vs Experience Benchmarking)
################################################################################

cat("\n=== Analysis 13B: Mean Salary Comparison by Year (Status Quo vs EB) ===\n")

# Create comparison table for mean salaries
mean_comparison <- h1b_policy %>%
  filter(!is.na(PW_year)) %>%
  group_by(PW_year) %>%
  summarise(
    status_quo = mean(petition_annual_pay_clean[eligible_status_quo], na.rm = TRUE),
    experience_benchmarking = mean(petition_annual_pay_clean[eligible_eb], na.rm = TRUE),
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

print(mean_comparison)

# Create formatted table for display
p13b <- gridExtra::tableGrob(
  mean_comparison %>%
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
# ANALYSIS 13C: Underpayment by Prior Visa Status
################################################################################

cat("\n=== Analysis 13C: Underpayment by Prior Visa Status ===\n")

# Calculate underpayment rate by prior visa status
underpay_by_prior_status_full <- h1b_policy %>%
  filter(!is.na(petition_beneficiary_classif)) %>%
  mutate(
    # Exclude NA, UU, UN from top 5 consideration
    is_special = petition_beneficiary_classif %in% c("NA", "UU", "UN")
  ) %>%
  group_by(petition_beneficiary_classif) %>%
  summarise(
    n_total = n(),
    n_underpaid = sum(petition_annual_pay_clean < pw_p50, na.rm = TRUE),
    is_special = first(is_special),
    .groups = "drop"
  ) %>%
  arrange(desc(n_total))

# Identify top 5 (excluding NA/UU/UN)
top5_statuses <- underpay_by_prior_status_full %>%
  filter(!is_special) %>%
  slice_head(n = 5) %>%
  pull(petition_beneficiary_classif)

# Create simplified version with top 5 + "All Other"
underpay_by_prior_status <- underpay_by_prior_status_full %>%
  mutate(
    status_label = ifelse(petition_beneficiary_classif %in% top5_statuses,
                          as.character(petition_beneficiary_classif),
                          "All Other")
  ) %>%
  group_by(status_label) %>%
  summarise(
    n_total = sum(n_total),
    n_underpaid = sum(n_underpaid),
    .groups = "drop"
  ) %>%
  mutate(
    pct_underpaid = (n_underpaid / n_total) * 100,
    # Create sort order: top 5 by size, then "All Other" at end
    sort_order = ifelse(status_label == "All Other", -1, n_total),
    status_label = factor(status_label, levels = unique(status_label[order(-sort_order)]))
  ) %>%
  select(-sort_order)

print(underpay_by_prior_status)

# Create bar chart
p13c <- ggplot(underpay_by_prior_status, aes(x = status_label, y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            vjust = -0.5, size = 3.5, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                    limits = c(0, max(underpay_by_prior_status$pct_underpaid) * 1.1)) +
  labs(
    title = "Underpayment Rate by Prior Visa Status (Top 5)",
    subtitle = "Share of workers paid below age-adjusted prevailing wage (pw_p50)",
    x = "Prior Visa Status",
    y = "Underpayment Rate (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

################################################################################
# ANALYSIS 13D: Underpayment F-1 vs All Others
################################################################################

cat("\n=== Analysis 13D: Underpayment F-1 vs All Others ===\n")

# Simple F-1 vs All Others comparison
underpay_f1_vs_others <- h1b_policy %>%
  filter(!is.na(petition_beneficiary_classif)) %>%
  mutate(
    status_group = ifelse(petition_beneficiary_classif == "F1", "F-1", "All Other")
  ) %>%
  group_by(status_group) %>%
  summarise(
    n_total = n(),
    n_underpaid = sum(petition_annual_pay_clean < pw_p50, na.rm = TRUE),
    pct_underpaid = (n_underpaid / n_total) * 100,
    .groups = "drop"
  ) %>%
  mutate(
    status_group = factor(status_group, levels = c("F-1", "All Other"))
  )

print(underpay_f1_vs_others)

# Create bar chart
p13d <- ggplot(underpay_f1_vs_others, aes(x = status_group, y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue, width = 0.6) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            vjust = -0.5, size = 5, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                    limits = c(0, max(underpay_f1_vs_others$pct_underpaid) * 1.15)) +
  labs(
    title = "Underpayment Rate: F-1 vs All Other Prior Visa Statuses",
    subtitle = "Share of workers paid below age-adjusted prevailing wage (pw_p50)",
    x = "Prior Visa Status",
    y = "Underpayment Rate (%)"
  ) +
  theme_ifp()

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
    title = "Eligible Population: Age Distribution by Policy",
    subtitle = "Solid line = median, dashed lines = 25th and 75th percentiles",
    x = "Age",
    y = "Count"
  ) +
  theme_ifp() +
  theme(strip.text = element_text(face = "bold", size = 10))

################################################################################
# ANALYSIS 15: Eligible Population - Share with PhD by Policy
################################################################################

cat("\n=== Analysis 15: Eligible Population PhD Share ===\n")

# Calculate share of PhD holders among eligible workers for each policy
eligible_phd_stats <- h1b_policy %>%
  mutate(has_phd = highest_ed == "PhD") %>%
  summarise(
    Status_Quo_total = sum(eligible_status_quo, na.rm = TRUE),
    Status_Quo_phd = sum(eligible_status_quo & has_phd, na.rm = TRUE),

    Rule_2021_total = sum(eligible_2021, na.rm = TRUE),
    Rule_2021_phd = sum(eligible_2021 & has_phd, na.rm = TRUE),

    P50_total = sum(eligible_p50, na.rm = TRUE),
    P50_phd = sum(eligible_p50 & has_phd, na.rm = TRUE),

    EB_total = sum(eligible_eb, na.rm = TRUE),
    EB_phd = sum(eligible_eb & has_phd, na.rm = TRUE)
  ) %>%
  pivot_longer(everything(), names_to = c("policy", ".value"), names_pattern = "(.*)_(.*)") %>%
  mutate(
    pct_phd = (phd / total) * 100,
    policy = factor(case_when(
      policy == "Status_Quo" ~ "Status Quo",
      policy == "Rule_2021" ~ "2021 Rule",
      policy == "P50" ~ "50th Percentile Minimum",
      policy == "EB" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"))
  )

print(eligible_phd_stats)

p15 <- ggplot(eligible_phd_stats, aes(x = policy, y = pct_phd)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_phd)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Eligible Population: Share with PhD by Policy",
    subtitle = "Percentage of eligible workers with doctoral degrees",
    x = NULL,
    y = "Share with PhD (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 16-23: WEIGHTED LOTTERY SIMULATION
#
# BACKGROUND: H-1B visas are currently allocated through a random lottery when
# demand exceeds supply (which it does every year). Various proposals would
# replace the random lottery with a "weighted" lottery where higher-paid workers
# get more lottery entries.
#
# WEIGHTED LOTTERY CONCEPT:
# Instead of giving everyone 1 lottery entry, we give people 1-4 entries based
# on how much they're paid. Someone with 4 entries has 4× the chance of winning
# compared to someone with 1 entry.
#
# WEIGHT ASSIGNMENT BY POLICY:
#
# 1. STATUS QUO WEIGHTED:
#    - Uses OFLC wage levels (Level1_full, Level2_full, Level3_full, Level4_full)
#    - 1 entry if paid at Level I or II
#    - 2 entries if paid at Level III
#    - 3 entries if paid at Level IV
#    - 4 entries if paid above Level IV
#    - ISSUE: OFLC levels vary wildly by occupation and don't account for age
#
# 2. 2021 RULE WEIGHTED:
#    - Uses petition_percentile_combined (within-occupation percentile)
#    - 1 entry at 35th-52nd percentile
#    - 2 entries at 53rd-71st percentile
#    - 3 entries at 72nd-89th percentile
#    - 4 entries at 90th+ percentile
#    - ISSUE: Still doesn't account for age/experience
#
# 3. EXPERIENCE BENCHMARKING WEIGHTED:
#    - Uses age-adjusted percentiles (pw_p50, pw_p62, pw_p75, pw_p90)
#    - 1 entry at 50th-61st percentile for your age
#    - 2 entries at 62nd-74th percentile for your age
#    - 3 entries at 75th-89th percentile for your age
#    - 4 entries at 90th+ percentile for your age
#    - ADVANTAGE: Accounts for experience via age
#
# SIMULATION METHOD:
# We simulate the weighted lottery by "expanding" the dataset: each petition
# gets duplicated by its weight. Someone with weight=3 appears 3 times in the
# expanded dataset. We then calculate statistics on this expanded dataset to
# represent "who would be selected" under the weighted lottery.
#
# INTERPRETATION:
# "Weighted lottery" analyses (pages 16-23) show characteristics of selected
# workers, while "eligible population" analyses (pages 1-15) show characteristics
# of applicants. The difference reveals how the weighted lottery changes outcomes.
################################################################################

cat("\n=== Analysis 16: Weighted Lottery Simulation - Assign Weights ===\n")

# Assign lottery weights (1-4 entries) based on each policy's criteria
h1b_lottery <- h1b_policy %>%
  filter(!is.na(PW_year), !is.na(age)) %>%
  mutate(
    # STATUS QUO WEIGHTED: Based on OFLC Level thresholds
    # Uses _full variables (annual wages) to determine weight
    weight_status_quo = case_when(
      !eligible_status_quo ~ 0,                         # Ineligible = no entries
      petition_annual_pay_clean >= Level4_full ~ 4,    # Above Level IV = 4 entries
      petition_annual_pay_clean >= Level3_full ~ 3,    # Level III-IV = 3 entries
      petition_annual_pay_clean >= Level2_full ~ 2,    # Level II-III = 2 entries
      petition_annual_pay_clean >= Level1_full ~ 1,    # Level I-II = 1 entry
      TRUE ~ 1                                          # Below Level I but eligible = 1 entry
    ),

    # 2021 RULE WEIGHTED: Based on within-occupation percentile thresholds
    # Uses same percentile cutoffs as eligibility (35, 53, 72, 90)
    weight_2021 = case_when(
      !eligible_2021 ~ 0,                               # Ineligible = no entries
      petition_percentile_combined >= 90 ~ 4,           # 90th+ percentile = 4 entries
      petition_percentile_combined >= 72 ~ 3,           # 72nd-89th = 3 entries
      petition_percentile_combined >= 53 ~ 2,           # 53rd-71st = 2 entries
      petition_percentile_combined >= 35 ~ 1,           # 35th-52nd = 1 entry
      TRUE ~ 0                                          # Below 35th = ineligible
    ),

    # EXPERIENCE BENCHMARKING WEIGHTED: Based on age-adjusted percentiles
    # Uses pw_p50, pw_p62, pw_p75, pw_p90 (age-specific thresholds)
    # These come from the Mincer regression (Script 06)
    weight_eb = case_when(
      !eligible_eb ~ 0,                                 # Ineligible = no entries
      petition_annual_pay_clean >= pw_p90 ~ 4,         # 90th+ for age = 4 entries
      petition_annual_pay_clean >= pw_p75 ~ 3,         # 75th-89th for age = 3 entries
      petition_annual_pay_clean >= pw_p62 ~ 2,         # 62nd-74th for age = 2 entries
      petition_annual_pay_clean >= pw_p50 ~ 1,         # 50th-61st for age = 1 entry
      TRUE ~ 0                                          # Below 50th for age = ineligible
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
# ANALYSIS 17: Weighted Lottery - Median/Mean Salary by Year
################################################################################

cat("\n=== Analysis 17: Weighted Lottery Salaries by Year ===\n")

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
p16 <- ggplot(lottery_salary_stats, aes(x = PW_year, y = median_salary, color = policy, group = policy)) +
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
p17 <- ggplot(lottery_salary_stats, aes(x = PW_year, y = mean_salary, color = policy, group = policy)) +
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
# ANALYSIS 18: Weighted Lottery - Age Distribution
################################################################################

cat("\n=== Analysis 18: Weighted Lottery Age Distribution ===\n")

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

p18 <- ggplot(lottery_age_expanded, aes(x = age)) +
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
# ANALYSIS 19: Weighted Lottery - Median Wage Premium by Year
################################################################################

cat("\n=== Analysis 19: Weighted Lottery Median Wage Premium ===\n")

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
p19 <- ggplot(lottery_premium_stats, aes(x = PW_year, y = median_premium_dollars, color = policy, group = policy)) +
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
    subtitle = "Dollar amount above/below what similarly-qualified Americans earn (weighted by lottery entries)",
    x = "Fiscal Year",
    y = "Median Wage Premium ($)",
    color = "Policy"
  ) +
  theme_ifp() +
  theme(legend.position = "bottom")

# Plot median wage premium in percent by year
p20 <- ggplot(lottery_premium_stats, aes(x = PW_year, y = median_premium_pct, color = policy, group = policy)) +
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
    subtitle = "Percent above/below what similarly-qualified Americans earn (weighted by lottery entries)",
    x = "Fiscal Year",
    y = "Median Wage Premium (%)",
    color = "Policy"
  ) +
  theme_ifp() +
  theme(legend.position = "bottom")

################################################################################
# ANALYSIS 20: Weighted Lottery - Share with PhD
################################################################################

cat("\n=== Analysis 20: Weighted Lottery PhD Share ===\n")

# Calculate share of PhD holders in weighted lottery for each policy
lottery_phd_stats <- h1b_lottery %>%
  mutate(has_phd = highest_ed == "PhD") %>%
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

# Create expanded dataset (weighted by lottery entries)
lottery_phd_expanded <- lottery_phd_stats %>%
  uncount(weights = weight)

# Calculate percentage with PhD for each policy
phd_share <- lottery_phd_expanded %>%
  group_by(policy) %>%
  summarise(
    total = n(),
    n_phd = sum(has_phd, na.rm = TRUE),
    pct_phd = mean(has_phd, na.rm = TRUE) * 100,
    .groups = "drop"
  )

print(phd_share)

# Create bar chart
p21 <- ggplot(phd_share, aes(x = policy, y = pct_phd)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_phd)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Weighted Lottery Simulation: Share with PhD",
    subtitle = "Percentage of lottery winners with doctoral degrees",
    x = NULL,
    y = "Share with PhD (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 21: Weighted Lottery - Share with Prior F-1 Status
################################################################################

cat("\n=== Analysis 21: Weighted Lottery F-1 Status ===\n")

# Calculate share of F-1 holders in weighted lottery for each policy
lottery_f1_stats <- h1b_lottery %>%
  mutate(has_f1 = petition_beneficiary_classif == "F1") %>%
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

# Create expanded dataset (weighted by lottery entries)
lottery_f1_expanded <- lottery_f1_stats %>%
  uncount(weights = weight)

# Calculate percentage with F-1 status for each policy
f1_share <- lottery_f1_expanded %>%
  group_by(policy) %>%
  summarise(
    total = n(),
    n_f1 = sum(has_f1, na.rm = TRUE),
    pct_f1 = mean(has_f1, na.rm = TRUE) * 100,
    .groups = "drop"
  )

print(f1_share)

# Create bar chart
p22 <- ggplot(f1_share, aes(x = policy, y = pct_f1)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_f1)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Weighted Lottery Simulation: Share with Prior F-1 Status",
    subtitle = "Percentage of lottery winners with F-1 student visa background",
    x = NULL,
    y = "Share with Prior F-1 (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 22: Weighted Lottery - Share Underpaid
################################################################################

cat("\n=== Analysis 22: Weighted Lottery Underpayment Share ===\n")

# Calculate share underpaid in weighted lottery for each policy
lottery_underpay_stats <- h1b_lottery %>%
  mutate(is_underpaid = petition_annual_pay_clean < pw_p50) %>%
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

# Create expanded dataset (weighted by lottery entries)
lottery_underpay_expanded <- lottery_underpay_stats %>%
  uncount(weights = weight)

# Calculate percentage underpaid for each policy
underpay_share <- lottery_underpay_expanded %>%
  group_by(policy) %>%
  summarise(
    total = n(),
    n_underpaid = sum(is_underpaid, na.rm = TRUE),
    pct_underpaid = mean(is_underpaid, na.rm = TRUE) * 100,
    .groups = "drop"
  )

print(underpay_share)

# Create bar chart
p23 <- ggplot(underpay_share, aes(x = policy, y = pct_underpaid)) +
  geom_col(fill = ifp_colors$red) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Weighted Lottery Simulation: Share Underpaid",
    subtitle = "Percentage of lottery winners paid less than similarly-qualified Americans",
    x = NULL,
    y = "Share Underpaid (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 23-29 & 31-39: INDUSTRY AND OCCUPATION ANALYSES
#
# These analyses break down H-1B petitions by industry (NAICS code) and
# occupation (SOC title) to understand:
# 1. Which industries/occupations have highest underpayment rates
# 2. How policy proposals change industry/occupation mix
# 3. Whether underpayment varies by industry/occupation
#
# INDUSTRY CLASSIFICATION (NAICS):
# - petition_employer_naics: Employer's 6-digit NAICS code
# - Top industries are dominated by tech (541511, 541512, 511210)
# - "999999" = Unknown/Not Specified (data quality issue)
#
# OCCUPATION CLASSIFICATION (SOC):
# - SOC_TITLE: Occupation title (e.g., "SOFTWARE DEVELOPERS")
# - Top occupations are tech-heavy (software developers, computer systems analysts)
#
# KEY QUESTIONS:
# - Are certain industries systematically underpaying H-1B workers?
# - Do policy proposals change the industry mix (e.g., favor/disfavor certain sectors)?
# - Does weighted lottery shift composition toward higher-paying industries?
#
# ANALYSIS STRUCTURE:
# - Analyses 23-24: Underpayment rates by industry/occupation (eligible population)
# - Analyses 25-26: Industry mix across policies (% in each industry)
# - Analyses 27-28: Occupation mix across policies (% in each occupation)
# - Analyses 31-32: Industry underpayment rates by policy (policy comparison)
# - Analyses 33-34: Occupation underpayment rates by policy (policy comparison)
################################################################################

################################################################################
# ANALYSIS 23: Underpayment by Top 10 Industries (Eligible Population)
################################################################################

cat("\n=== Analysis 23: Underpayment by Top 10 Industries ===\n")

# NAICS code lookup for top industries
# Note: Some codes are 5-digit (broader categories), others are 6-digit (specific)
naics_lookup <- c(
  "541511" = "Custom Computer Programming",
  "541512" = "Computer Systems Design",
  "511210" = "Software Publishers",
  "54151" = "Computer Systems Design (general)",
  "45411" = "Electronic Shopping/Mail-Order",
  "518210" = "Data Processing/Hosting",
  "541330" = "Engineering Services",
  "541519" = "Other Computer Related Services",
  "999999" = "Unknown/Not Specified",
  "523110" = "Investment Banking",
  "334111" = "Electronic Computer Manufacturing",
  "541611" = "Administrative Management Consulting",
  "454110" = "Electronic Shopping",
  "541211" = "Offices of CPAs",
  "5416" = "Management/Technical Consulting"
)

# Find top 10 industries by petition count in eligible population (status quo)
top_industries <- h1b_policy %>%
  filter(eligible_status_quo, !is.na(petition_employer_naics)) %>%
  dplyr::count(petition_employer_naics, sort = TRUE) %>%
  head(10) %>%
  pull(petition_employer_naics)

# Calculate underpayment rates for top 10 industries
industry_underpay <- h1b_policy %>%
  filter(eligible_status_quo,
         petition_employer_naics %in% top_industries) %>%
  mutate(
    industry_label = case_when(
      petition_employer_naics == "541511" ~ "Custom Computer Programming\n(541511)",
      petition_employer_naics == "541512" ~ "Computer Systems Design\n(541512)",
      petition_employer_naics == "511210" ~ "Software Publishers\n(511210)",
      petition_employer_naics == "54151" ~ "Computer Systems Design\n(54151)",
      petition_employer_naics == "45411" ~ "Electronic Shopping\n(45411)",
      petition_employer_naics == "518210" ~ "Data Processing/Hosting\n(518210)",
      petition_employer_naics == "541330" ~ "Engineering Services\n(541330)",
      petition_employer_naics == "541519" ~ "Other Computer Services\n(541519)",
      petition_employer_naics == "999999" ~ "Unknown/Not Specified\n(999999)",
      petition_employer_naics == "523110" ~ "Investment Banking\n(523110)",
      TRUE ~ paste0("NAICS ", petition_employer_naics)
    )
  ) %>%
  group_by(industry_label) %>%
  summarise(
    n = n(),
    n_underpaid = sum(petition_annual_pay_clean < pw_p50, na.rm = TRUE),
    pct_underpaid = mean(petition_annual_pay_clean < pw_p50, na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  arrange(desc(n))

print(industry_underpay)

p24 <- ggplot(industry_underpay, aes(x = reorder(industry_label, n), y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            hjust = -0.1, size = 3.5, color = ifp_colors$rich_black) +
  coord_flip() +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Eligible Population: Underpayment Rates by Top 10 Industries",
    subtitle = "Percentage paying less than similarly-qualified Americans (ordered by industry size)",
    x = NULL,
    y = "Underpaid (%)"
  ) +
  theme_ifp()

################################################################################
# ANALYSIS 24: Underpayment by Top 10 Occupations (Eligible Population)
################################################################################

cat("\n=== Analysis 24: Underpayment by Top 10 Occupations ===\n")

# Find top 10 occupations by petition count in eligible population (status quo)
top_occupations <- h1b_policy %>%
  filter(eligible_status_quo, !is.na(SOC_TITLE)) %>%
  dplyr::count(SOC_TITLE, sort = TRUE) %>%
  head(10) %>%
  pull(SOC_TITLE)

# Calculate underpayment rates for top 10 occupations
occupation_underpay <- h1b_policy %>%
  filter(eligible_status_quo,
         SOC_TITLE %in% top_occupations) %>%
  mutate(
    occupation_label = str_to_title(SOC_TITLE)
  ) %>%
  group_by(occupation_label) %>%
  summarise(
    n = n(),
    n_underpaid = sum(petition_annual_pay_clean < pw_p50, na.rm = TRUE),
    pct_underpaid = mean(petition_annual_pay_clean < pw_p50, na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  arrange(desc(n))

print(occupation_underpay)

p25 <- ggplot(occupation_underpay, aes(x = reorder(occupation_label, n), y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            hjust = -0.1, size = 3.5, color = ifp_colors$rich_black) +
  coord_flip() +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Eligible Population: Underpayment Rates by Top 10 Occupations",
    subtitle = "Percentage paying less than similarly-qualified Americans (ordered by occupation size)",
    x = NULL,
    y = "Underpaid (%)"
  ) +
  theme_ifp()

################################################################################
# ANALYSIS 25: Industry Mix - Eligible Population
################################################################################

cat("\n=== Analysis 25: Industry Mix - Eligible Population ===\n")

# Calculate industry distribution for each policy's eligible population
# First get top 10 industries overall (across all policies)
top_10_industries <- h1b_policy %>%
  filter(eligible_status_quo, !is.na(petition_employer_naics)) %>%
  dplyr::count(petition_employer_naics, sort = TRUE) %>%
  head(10) %>%
  pull(petition_employer_naics)

industry_mix_eligible <- h1b_policy %>%
  filter(!is.na(petition_employer_naics)) %>%
  mutate(
    industry_label = case_when(
      !petition_employer_naics %in% top_10_industries ~ "All Other",
      petition_employer_naics == "541511" ~ "Custom Computer Programming",
      petition_employer_naics == "541512" ~ "Computer Systems Design",
      petition_employer_naics == "511210" ~ "Software Publishers",
      petition_employer_naics == "54151" ~ "Computer Systems Design",
      petition_employer_naics == "45411" ~ "Electronic Shopping",
      petition_employer_naics == "518210" ~ "Data Processing/Hosting",
      petition_employer_naics == "541330" ~ "Engineering Services",
      petition_employer_naics == "541519" ~ "Other Computer Services",
      petition_employer_naics == "999999" ~ "Unknown/Not Specified",
      petition_employer_naics == "523110" ~ "Investment Banking",
      TRUE ~ paste0("NAICS ", petition_employer_naics)
    )
  ) %>%
  pivot_longer(
    cols = c(eligible_status_quo, eligible_2021, eligible_p50, eligible_eb),
    names_to = "policy",
    values_to = "eligible"
  ) %>%
  filter(eligible) %>%
  mutate(
    policy = factor(case_when(
      policy == "eligible_status_quo" ~ "Status Quo",
      policy == "eligible_2021" ~ "2021 Rule",
      policy == "eligible_p50" ~ "50th Percentile Minimum",
      policy == "eligible_eb" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"))
  ) %>%
  group_by(policy, industry_label) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(policy) %>%
  mutate(pct = (n / sum(n)) * 100) %>%
  ungroup()

print(industry_mix_eligible %>% arrange(policy, desc(pct)))

p26 <- ggplot(industry_mix_eligible, aes(x = reorder(industry_label, pct), y = pct)) +
  geom_col(fill = ifp_colors$dark_blue) +
  coord_flip() +
  facet_wrap(~policy, ncol = 2, scales = "free_y") +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.1))) +
  labs(
    title = "Eligible Population: Industry Mix by Policy (Top 10 Industries)",
    subtitle = "Share of eligible petitions in each industry",
    x = NULL,
    y = "Share (%)"
  ) +
  theme_ifp() +
  theme(strip.text = element_text(face = "bold", size = 9))

################################################################################
# ANALYSIS 26: Industry Mix - Weighted Lottery
################################################################################

cat("\n=== Analysis 26: Industry Mix - Weighted Lottery ===\n")

# Calculate weighted industry distribution for lottery simulation
# Use same top 10 industries as eligible population
industry_mix_lottery <- h1b_lottery %>%
  filter(!is.na(petition_employer_naics)) %>%
  mutate(
    industry_label = case_when(
      !petition_employer_naics %in% top_10_industries ~ "All Other",
      petition_employer_naics == "541511" ~ "Custom Computer Programming",
      petition_employer_naics == "541512" ~ "Computer Systems Design",
      petition_employer_naics == "511210" ~ "Software Publishers",
      petition_employer_naics == "54151" ~ "Computer Systems Design",
      petition_employer_naics == "45411" ~ "Electronic Shopping",
      petition_employer_naics == "518210" ~ "Data Processing/Hosting",
      petition_employer_naics == "541330" ~ "Engineering Services",
      petition_employer_naics == "541519" ~ "Other Computer Services",
      petition_employer_naics == "999999" ~ "Unknown/Not Specified",
      petition_employer_naics == "523110" ~ "Investment Banking",
      TRUE ~ paste0("NAICS ", petition_employer_naics)
    )
  ) %>%
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

# Expand by weight and calculate distribution
industry_mix_lottery_expanded <- industry_mix_lottery %>%
  uncount(weights = weight) %>%
  group_by(policy, industry_label) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(policy) %>%
  mutate(pct = (n / sum(n)) * 100) %>%
  ungroup()

print(industry_mix_lottery_expanded %>% arrange(policy, desc(pct)))

p27 <- ggplot(industry_mix_lottery_expanded, aes(x = reorder(industry_label, pct), y = pct)) +
  geom_col(fill = ifp_colors$dark_blue) +
  coord_flip() +
  facet_wrap(~policy, ncol = 1, scales = "free_y") +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.1))) +
  labs(
    title = "Weighted Lottery Simulation: Industry Mix (Top 10 Industries)",
    subtitle = "Share of lottery winners in each industry (weighted by entries)",
    x = NULL,
    y = "Share (%)"
  ) +
  theme_ifp() +
  theme(strip.text = element_text(face = "bold", size = 10))

################################################################################
# ANALYSIS 27: Occupation Mix - Eligible Population
################################################################################

cat("\n=== Analysis 27: Occupation Mix - Eligible Population ===\n")

# Calculate occupation distribution for each policy's eligible population
# First get top 10 occupations overall (across all policies)
top_10_occupations <- h1b_policy %>%
  filter(eligible_status_quo, !is.na(SOC_TITLE)) %>%
  dplyr::count(SOC_TITLE, sort = TRUE) %>%
  head(10) %>%
  pull(SOC_TITLE)

occupation_mix_eligible <- h1b_policy %>%
  filter(!is.na(SOC_TITLE)) %>%
  mutate(
    occupation_label = if_else(
      SOC_TITLE %in% top_10_occupations,
      str_to_title(SOC_TITLE),
      "All Other"
    )
  ) %>%
  pivot_longer(
    cols = c(eligible_status_quo, eligible_2021, eligible_p50, eligible_eb),
    names_to = "policy",
    values_to = "eligible"
  ) %>%
  filter(eligible) %>%
  mutate(
    policy = factor(case_when(
      policy == "eligible_status_quo" ~ "Status Quo",
      policy == "eligible_2021" ~ "2021 Rule",
      policy == "eligible_p50" ~ "50th Percentile Minimum",
      policy == "eligible_eb" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"))
  ) %>%
  group_by(policy, occupation_label) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(policy) %>%
  mutate(pct = (n / sum(n)) * 100) %>%
  ungroup()

print(occupation_mix_eligible %>% arrange(policy, desc(pct)))

p28 <- ggplot(occupation_mix_eligible, aes(x = reorder(occupation_label, pct), y = pct)) +
  geom_col(fill = ifp_colors$dark_blue) +
  coord_flip() +
  facet_wrap(~policy, ncol = 2, scales = "free_y") +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.1))) +
  labs(
    title = "Eligible Population: Occupation Mix by Policy (Top 10 Occupations)",
    subtitle = "Share of eligible petitions in each occupation",
    x = NULL,
    y = "Share (%)"
  ) +
  theme_ifp() +
  theme(strip.text = element_text(face = "bold", size = 9))

################################################################################
# ANALYSIS 28: Occupation Mix - Weighted Lottery
################################################################################

cat("\n=== Analysis 28: Occupation Mix - Weighted Lottery ===\n")

# Calculate weighted occupation distribution for lottery simulation
# Use same top 10 occupations as eligible population
occupation_mix_lottery <- h1b_lottery %>%
  filter(!is.na(SOC_TITLE)) %>%
  mutate(
    occupation_label = if_else(
      SOC_TITLE %in% top_10_occupations,
      str_to_title(SOC_TITLE),
      "All Other"
    )
  ) %>%
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

# Expand by weight and calculate distribution
occupation_mix_lottery_expanded <- occupation_mix_lottery %>%
  uncount(weights = weight) %>%
  group_by(policy, occupation_label) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(policy) %>%
  mutate(pct = (n / sum(n)) * 100) %>%
  ungroup()

print(occupation_mix_lottery_expanded %>% arrange(policy, desc(pct)))

p29 <- ggplot(occupation_mix_lottery_expanded, aes(x = reorder(occupation_label, pct), y = pct)) +
  geom_col(fill = ifp_colors$dark_blue) +
  coord_flip() +
  facet_wrap(~policy, ncol = 1, scales = "free_y") +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.1))) +
  labs(
    title = "Weighted Lottery Simulation: Occupation Mix (Top 10 Occupations)",
    subtitle = "Share of lottery winners in each occupation (weighted by entries)",
    x = NULL,
    y = "Share (%)"
  ) +
  theme_ifp() +
  theme(strip.text = element_text(face = "bold", size = 10))

################################################################################
# ANALYSIS 29-35: LIFETIME EARNINGS ANALYSES
#
# These analyses incorporate the NPV calculations from Script 09 to estimate
# the total economic value contributed by H-1B workers over their careers.
#
# LIFETIME EARNINGS VARIABLES:
# - lifetime_earnings_3pct: NPV of expected lifetime earnings using 3% discount rate
# - lifetime_earnings_7pct: NPV of expected lifetime earnings using 7% discount rate
#
# HOW THEY'RE CALCULATED (from Script 09):
# For each H-1B worker, we:
# 1. Look up their age
# 2. Get the NPV multiplier for that age from ACS data
# 3. Multiply their current salary by the multiplier
# Example: 30-year-old earning $100k with 3% multiplier of 31.77
#          → lifetime earnings = $100k × 31.77 = $3.177 million
#
# WHY TWO DISCOUNT RATES?
# - 3% discount rate: More patient view, values future earnings more highly
# - 7% discount rate: More impatient view, discounts future earnings more steeply
# - 3% is closer to historical Treasury rates; 7% is closer to private discount rates
#
# KEY INSIGHT:
# Policies that select younger workers (Experience Benchmarking) will show higher
# lifetime earnings because younger workers have more earning years ahead. This
# measures the long-term economic contribution of each policy's selected population.
#
# COMPARISON:
# - Eligible Population (Analysis 29): Average lifetime value of applicants
# - Weighted Lottery (Analysis 30): Average lifetime value of selected workers
#   (shows whether weighted lottery selects higher or lower lifetime earners)
################################################################################

cat("\n=== Analysis 29: Lifetime Earnings - Eligible Population ===\n")

# Calculate median/mean lifetime earnings for eligible workers under each policy
lifetime_eligible_stats <- h1b_policy %>%
  filter(!is.na(lifetime_earnings_3pct), !is.na(lifetime_earnings_7pct)) %>%
  summarise(
    across(c(eligible_status_quo, eligible_2021, eligible_p50, eligible_eb),
           ~list(tibble(
             eligible = .x,
             lifetime_3pct = lifetime_earnings_3pct,
             lifetime_7pct = lifetime_earnings_7pct
           )))
  ) %>%
  pivot_longer(everything(), names_to = "policy", values_to = "data") %>%
  unnest(data) %>%
  filter(eligible) %>%  # Only include eligible workers
  group_by(policy) %>%
  summarise(
    median_lifetime_3pct = median(lifetime_3pct, na.rm = TRUE),
    mean_lifetime_3pct = mean(lifetime_3pct, na.rm = TRUE),
    median_lifetime_7pct = median(lifetime_7pct, na.rm = TRUE),
    mean_lifetime_7pct = mean(lifetime_7pct, na.rm = TRUE),
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

print(lifetime_eligible_stats)

# Median lifetime earnings (3% discount)
p30 <- ggplot(lifetime_eligible_stats, aes(x = policy, y = median_lifetime_3pct)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = paste0("$", round(median_lifetime_3pct / 1e6, 2), "M")),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_dollar(scale = 1/1e6, suffix = "M"),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Eligible Population: Median Expected Lifetime Earnings",
    subtitle = "Using 3% discount rate",
    x = NULL,
    y = "Median Lifetime Earnings"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

# Mean lifetime earnings (3% discount)
p31 <- ggplot(lifetime_eligible_stats, aes(x = policy, y = mean_lifetime_3pct)) +
  geom_col(fill = ifp_colors$purple) +
  geom_text(aes(label = paste0("$", round(mean_lifetime_3pct / 1e6, 2), "M")),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_dollar(scale = 1/1e6, suffix = "M"),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Eligible Population: Mean Expected Lifetime Earnings",
    subtitle = "Using 3% discount rate",
    x = NULL,
    y = "Mean Lifetime Earnings"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

# Median lifetime earnings (7% discount)
p32 <- ggplot(lifetime_eligible_stats, aes(x = policy, y = median_lifetime_7pct)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = paste0("$", round(median_lifetime_7pct / 1e6, 2), "M")),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_dollar(scale = 1/1e6, suffix = "M"),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Eligible Population: Median Expected Lifetime Earnings",
    subtitle = "Using 7% discount rate",
    x = NULL,
    y = "Median Lifetime Earnings"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 30: Lifetime Earnings - Weighted Lottery by Policy
################################################################################

cat("\n=== Analysis 30: Lifetime Earnings - Weighted Lottery ===\n")

# Calculate weighted median/mean lifetime earnings for lottery simulation
lifetime_lottery_data <- h1b_lottery %>%
  filter(!is.na(lifetime_earnings_3pct), !is.na(lifetime_earnings_7pct)) %>%
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

# Expand by weight and calculate statistics
lifetime_lottery_expanded <- lifetime_lottery_data %>%
  uncount(weights = weight)

lifetime_lottery_stats <- lifetime_lottery_expanded %>%
  group_by(policy) %>%
  summarise(
    median_lifetime_3pct = median(lifetime_earnings_3pct, na.rm = TRUE),
    mean_lifetime_3pct = mean(lifetime_earnings_3pct, na.rm = TRUE),
    median_lifetime_7pct = median(lifetime_earnings_7pct, na.rm = TRUE),
    mean_lifetime_7pct = mean(lifetime_earnings_7pct, na.rm = TRUE),
    .groups = "drop"
  )

print(lifetime_lottery_stats)

# Median lifetime earnings - lottery (3% discount)
p33 <- ggplot(lifetime_lottery_stats, aes(x = policy, y = median_lifetime_3pct)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = paste0("$", round(median_lifetime_3pct / 1e6, 2), "M")),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_dollar(scale = 1/1e6, suffix = "M"),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Weighted Lottery Simulation: Median Expected Lifetime Earnings",
    subtitle = "Using 3% discount rate (weighted by lottery entries)",
    x = NULL,
    y = "Median Lifetime Earnings"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

# Mean lifetime earnings - lottery (3% discount)
p34 <- ggplot(lifetime_lottery_stats, aes(x = policy, y = mean_lifetime_3pct)) +
  geom_col(fill = ifp_colors$purple) +
  geom_text(aes(label = paste0("$", round(mean_lifetime_3pct / 1e6, 2), "M")),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_dollar(scale = 1/1e6, suffix = "M"),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Weighted Lottery Simulation: Mean Expected Lifetime Earnings",
    subtitle = "Using 3% discount rate (weighted by lottery entries)",
    x = NULL,
    y = "Mean Lifetime Earnings"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

# Median lifetime earnings - lottery (7% discount)
p35 <- ggplot(lifetime_lottery_stats, aes(x = policy, y = median_lifetime_7pct)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = paste0("$", round(median_lifetime_7pct / 1e6, 2), "M")),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_dollar(scale = 1/1e6, suffix = "M"),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Weighted Lottery Simulation: Median Expected Lifetime Earnings",
    subtitle = "Using 7% discount rate (weighted by lottery entries)",
    x = NULL,
    y = "Median Lifetime Earnings"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 31: Underpayment by Industry - Eligible Population (Policy Comparison)
################################################################################

cat("\n=== Analysis 31: Underpayment by Industry - Eligible Population (Policy Comparison) ===\n")

# Calculate underpayment rates by industry for each policy
industry_underpay_policy <- h1b_policy %>%
  filter(!is.na(petition_employer_naics)) %>%
  mutate(
    industry_label = case_when(
      !petition_employer_naics %in% top_10_industries ~ "All Other",
      petition_employer_naics == "541511" ~ "Custom Computer\nProgramming",
      petition_employer_naics == "541512" ~ "Computer Systems\nDesign",
      petition_employer_naics == "511210" ~ "Software\nPublishers",
      petition_employer_naics == "54151" ~ "Computer Systems\nDesign (54151)",
      petition_employer_naics == "45411" ~ "Electronic\nShopping",
      petition_employer_naics == "518210" ~ "Data Processing/\nHosting",
      petition_employer_naics == "541330" ~ "Engineering\nServices",
      petition_employer_naics == "541519" ~ "Other Computer\nServices",
      petition_employer_naics == "999999" ~ "Unknown/\nNot Specified",
      petition_employer_naics == "523110" ~ "Investment\nBanking",
      TRUE ~ paste0("NAICS ", petition_employer_naics)
    )
  ) %>%
  # Calculate for each policy
  group_by(industry_label) %>%
  summarise(
    # Status Quo
    n_status_quo = sum(eligible_status_quo, na.rm = TRUE),
    n_underpaid_status_quo = sum(eligible_status_quo & petition_annual_pay_clean < pw_p50, na.rm = TRUE),
    pct_underpaid_status_quo = ifelse(n_status_quo > 0, (n_underpaid_status_quo / n_status_quo) * 100, NA),

    # 2021 Rule
    n_2021 = sum(eligible_2021, na.rm = TRUE),
    n_underpaid_2021 = sum(eligible_2021 & petition_annual_pay_clean < pw_p50, na.rm = TRUE),
    pct_underpaid_2021 = ifelse(n_2021 > 0, (n_underpaid_2021 / n_2021) * 100, NA),

    # Experience Benchmarking (always 0%)
    n_eb = sum(eligible_eb, na.rm = TRUE),
    pct_underpaid_eb = 0,

    .groups = "drop"
  ) %>%
  filter(n_status_quo >= 100) %>%  # Only industries with sufficient sample
  pivot_longer(
    cols = c(pct_underpaid_status_quo, pct_underpaid_2021, pct_underpaid_eb),
    names_to = "policy",
    values_to = "pct_underpaid"
  ) %>%
  mutate(
    policy = factor(case_when(
      policy == "pct_underpaid_status_quo" ~ "Status Quo",
      policy == "pct_underpaid_2021" ~ "2021 Rule",
      policy == "pct_underpaid_eb" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "Experience Benchmarking"))
  )

print(industry_underpay_policy %>% arrange(industry_label, policy))

# Add display column with minimum height for 0% bars (so they're visible)
# Sort by industry size (n_status_quo) with "All Other" always at bottom (after coord_flip)
industry_underpay_policy <- industry_underpay_policy %>%
  mutate(pct_display = pmax(pct_underpaid, 0.5)) %>%  # 0% shows as 0.5% sliver
  group_by(industry_label) %>%
  mutate(industry_size = first(n_status_quo)) %>%
  ungroup() %>%
  mutate(
    # Create sort key: "All Other" gets -Inf (first), others by size ascending
    # After coord_flip: first level = bottom, last level = top
    sort_order = ifelse(industry_label == "All Other", -Inf, industry_size),
    industry_label = factor(industry_label,
                           levels = unique(industry_label[order(sort_order)]))
  )

p36 <- ggplot(industry_underpay_policy, aes(x = industry_label, y = pct_display, fill = policy)) +
  geom_col(position = "dodge") +
  # Add text labels showing actual percentages (whole numbers)
  geom_text(aes(label = sprintf("%.0f%%", pct_underpaid), y = pct_underpaid),
            position = position_dodge(width = 0.9),
            hjust = -0.1, size = 3, color = ifp_colors$rich_black) +
  scale_fill_manual(values = c(
    "Status Quo" = ifp_colors$rich_black,
    "2021 Rule" = ifp_colors$purple,
    "Experience Benchmarking" = ifp_colors$dark_blue
  )) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +  # More space for labels
  labs(
    title = "Eligible Population: Underpayment Rates by Industry and Policy",
    subtitle = "Percentage of eligible workers paid less than similarly-qualified Americans (0% = no underpayment)",
    x = NULL,
    y = "Underpaid (%)",
    fill = "Policy"
  ) +
  coord_flip() +
  theme_ifp() +
  theme(legend.position = "bottom")

################################################################################
# ANALYSIS 32: Underpayment by Industry - Weighted Lottery (Policy Comparison)
################################################################################

cat("\n=== Analysis 32: Underpayment by Industry - Weighted Lottery (Policy Comparison) ===\n")

# Calculate weighted underpayment rates by industry for each policy
industry_underpay_lottery <- h1b_lottery %>%
  filter(!is.na(petition_employer_naics)) %>%
  mutate(
    industry_label = case_when(
      !petition_employer_naics %in% top_10_industries ~ "All Other",
      petition_employer_naics == "541511" ~ "Custom Computer\nProgramming",
      petition_employer_naics == "541512" ~ "Computer Systems\nDesign",
      petition_employer_naics == "511210" ~ "Software\nPublishers",
      petition_employer_naics == "54151" ~ "Computer Systems\nDesign (54151)",
      petition_employer_naics == "45411" ~ "Electronic\nShopping",
      petition_employer_naics == "518210" ~ "Data Processing/\nHosting",
      petition_employer_naics == "541330" ~ "Engineering\nServices",
      petition_employer_naics == "541519" ~ "Other Computer\nServices",
      petition_employer_naics == "999999" ~ "Unknown/\nNot Specified",
      petition_employer_naics == "523110" ~ "Investment\nBanking",
      TRUE ~ paste0("NAICS ", petition_employer_naics)
    ),
    is_underpaid = petition_annual_pay_clean < pw_p50
  ) %>%
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

# Expand by weight and calculate underpayment rates
industry_underpay_lottery_expanded <- industry_underpay_lottery %>%
  uncount(weights = weight) %>%
  group_by(policy, industry_label) %>%
  summarise(
    n = n(),
    n_underpaid = sum(is_underpaid, na.rm = TRUE),
    pct_underpaid = mean(is_underpaid, na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  filter(n >= 100)  # Only industries with sufficient sample

print(industry_underpay_lottery_expanded %>% arrange(industry_label, policy))

# Add display column with minimum height for 0% bars (so they're visible)
# Sort by industry size (Status Quo count) with "All Other" always at bottom (after coord_flip)
industry_underpay_lottery_expanded <- industry_underpay_lottery_expanded %>%
  mutate(pct_display = pmax(pct_underpaid, 0.5)) %>%  # 0% shows as 0.5% sliver
  group_by(industry_label) %>%
  mutate(industry_size = max(n[policy == "Status Quo"], na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    # Create sort key: "All Other" gets -Inf (first), others by size ascending
    # After coord_flip: first level = bottom, last level = top
    sort_order = ifelse(industry_label == "All Other", -Inf, industry_size),
    industry_label = factor(industry_label,
                           levels = unique(industry_label[order(sort_order)]))
  )

p37 <- ggplot(industry_underpay_lottery_expanded, aes(x = industry_label, y = pct_display, fill = policy)) +
  geom_col(position = "dodge") +
  # Add text labels showing actual percentages (whole numbers)
  geom_text(aes(label = sprintf("%.0f%%", pct_underpaid), y = pct_underpaid),
            position = position_dodge(width = 0.9),
            hjust = -0.1, size = 3, color = ifp_colors$rich_black) +
  scale_fill_manual(values = c(
    "Status Quo" = ifp_colors$rich_black,
    "2021 Rule" = ifp_colors$purple,
    "Experience Benchmarking" = ifp_colors$dark_blue
  )) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +  # More space for labels
  labs(
    title = "Weighted Lottery Simulation: Underpayment Rates by Industry and Policy",
    subtitle = "Percentage of lottery winners paid less than similarly-qualified Americans (0% = no underpayment)",
    x = NULL,
    y = "Underpaid (%)",
    fill = "Policy"
  ) +
  coord_flip() +
  theme_ifp() +
  theme(legend.position = "bottom")

################################################################################
# ANALYSIS 33: Underpayment by Occupation - Eligible Population (Policy Comparison)
################################################################################

cat("\n=== Analysis 33: Underpayment by Occupation - Eligible Population (Policy Comparison) ===\n")

# Calculate underpayment rates by occupation for each policy
occupation_underpay_policy <- h1b_policy %>%
  filter(!is.na(SOC_TITLE)) %>%
  mutate(
    occupation_label = if_else(
      SOC_TITLE %in% top_10_occupations,
      str_to_title(str_wrap(SOC_TITLE, width = 25)),
      "All Other"
    )
  ) %>%
  # Calculate for each policy
  group_by(occupation_label) %>%
  summarise(
    # Status Quo
    n_status_quo = sum(eligible_status_quo, na.rm = TRUE),
    n_underpaid_status_quo = sum(eligible_status_quo & petition_annual_pay_clean < pw_p50, na.rm = TRUE),
    pct_underpaid_status_quo = ifelse(n_status_quo > 0, (n_underpaid_status_quo / n_status_quo) * 100, NA),

    # 2021 Rule
    n_2021 = sum(eligible_2021, na.rm = TRUE),
    n_underpaid_2021 = sum(eligible_2021 & petition_annual_pay_clean < pw_p50, na.rm = TRUE),
    pct_underpaid_2021 = ifelse(n_2021 > 0, (n_underpaid_2021 / n_2021) * 100, NA),

    # Experience Benchmarking (always 0%)
    n_eb = sum(eligible_eb, na.rm = TRUE),
    pct_underpaid_eb = 0,

    .groups = "drop"
  ) %>%
  filter(n_status_quo >= 100) %>%  # Only occupations with sufficient sample
  pivot_longer(
    cols = c(pct_underpaid_status_quo, pct_underpaid_2021, pct_underpaid_eb),
    names_to = "policy",
    values_to = "pct_underpaid"
  ) %>%
  mutate(
    policy = factor(case_when(
      policy == "pct_underpaid_status_quo" ~ "Status Quo",
      policy == "pct_underpaid_2021" ~ "2021 Rule",
      policy == "pct_underpaid_eb" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "Experience Benchmarking"))
  )

print(occupation_underpay_policy %>% arrange(occupation_label, policy))

# Add display column with minimum height for 0% bars (so they're visible)
# Sort by occupation size (n_status_quo) with "All Other" always at bottom (after coord_flip)
occupation_underpay_policy <- occupation_underpay_policy %>%
  mutate(pct_display = pmax(pct_underpaid, 0.5)) %>%  # 0% shows as 0.5% sliver
  group_by(occupation_label) %>%
  mutate(occupation_size = first(n_status_quo)) %>%
  ungroup() %>%
  mutate(
    # Create sort key: "All Other" gets -Inf (first), others by size ascending
    # After coord_flip: first level = bottom, last level = top
    sort_order = ifelse(occupation_label == "All Other", -Inf, occupation_size),
    occupation_label = factor(occupation_label,
                             levels = unique(occupation_label[order(sort_order)]))
  )

p38 <- ggplot(occupation_underpay_policy, aes(x = occupation_label, y = pct_display, fill = policy)) +
  geom_col(position = "dodge") +
  # Add text labels showing actual percentages (whole numbers)
  geom_text(aes(label = sprintf("%.0f%%", pct_underpaid), y = pct_underpaid),
            position = position_dodge(width = 0.9),
            hjust = -0.1, size = 3, color = ifp_colors$rich_black) +
  scale_fill_manual(values = c(
    "Status Quo" = ifp_colors$rich_black,
    "2021 Rule" = ifp_colors$purple,
    "Experience Benchmarking" = ifp_colors$dark_blue
  )) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +  # More space for labels
  labs(
    title = "Eligible Population: Underpayment Rates by Occupation and Policy",
    subtitle = "Percentage of eligible workers paid less than similarly-qualified Americans (0% = no underpayment)",
    x = NULL,
    y = "Underpaid (%)",
    fill = "Policy"
  ) +
  coord_flip() +
  theme_ifp() +
  theme(legend.position = "bottom")

################################################################################
# ANALYSIS 34: Underpayment by Occupation - Weighted Lottery (Policy Comparison)
################################################################################

cat("\n=== Analysis 34: Underpayment by Occupation - Weighted Lottery (Policy Comparison) ===\n")

# Calculate weighted underpayment rates by occupation for each policy
occupation_underpay_lottery <- h1b_lottery %>%
  filter(!is.na(SOC_TITLE)) %>%
  mutate(
    occupation_label = if_else(
      SOC_TITLE %in% top_10_occupations,
      str_to_title(str_wrap(SOC_TITLE, width = 25)),
      "All Other"
    ),
    is_underpaid = petition_annual_pay_clean < pw_p50
  ) %>%
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

# Expand by weight and calculate underpayment rates
occupation_underpay_lottery_expanded <- occupation_underpay_lottery %>%
  uncount(weights = weight) %>%
  group_by(policy, occupation_label) %>%
  summarise(
    n = n(),
    n_underpaid = sum(is_underpaid, na.rm = TRUE),
    pct_underpaid = mean(is_underpaid, na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  filter(n >= 100)  # Only occupations with sufficient sample

print(occupation_underpay_lottery_expanded %>% arrange(occupation_label, policy))

# Add display column with minimum height for 0% bars (so they're visible)
# Sort by occupation size (Status Quo count) with "All Other" always at bottom (after coord_flip)
occupation_underpay_lottery_expanded <- occupation_underpay_lottery_expanded %>%
  mutate(pct_display = pmax(pct_underpaid, 0.5)) %>%  # 0% shows as 0.5% sliver
  group_by(occupation_label) %>%
  mutate(occupation_size = max(n[policy == "Status Quo"], na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(
    # Create sort key: "All Other" gets -Inf (first), others by size ascending
    # After coord_flip: first level = bottom, last level = top
    sort_order = ifelse(occupation_label == "All Other", -Inf, occupation_size),
    occupation_label = factor(occupation_label,
                             levels = unique(occupation_label[order(sort_order)]))
  )

p39 <- ggplot(occupation_underpay_lottery_expanded, aes(x = occupation_label, y = pct_display, fill = policy)) +
  geom_col(position = "dodge") +
  # Add text labels showing actual percentages (whole numbers)
  geom_text(aes(label = sprintf("%.0f%%", pct_underpaid), y = pct_underpaid),
            position = position_dodge(width = 0.9),
            hjust = -0.1, size = 3, color = ifp_colors$rich_black) +
  scale_fill_manual(values = c(
    "Status Quo" = ifp_colors$rich_black,
    "2021 Rule" = ifp_colors$purple,
    "Experience Benchmarking" = ifp_colors$dark_blue
  )) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +  # More space for labels
  labs(
    title = "Weighted Lottery Simulation: Underpayment Rates by Occupation and Policy",
    subtitle = "Percentage of lottery winners paid less than similarly-qualified Americans (0% = no underpayment)",
    x = NULL,
    y = "Underpaid (%)",
    fill = "Policy"
  ) +
  coord_flip() +
  theme_ifp() +
  theme(legend.position = "bottom")

################################################################################
# PDF EXPORT
#
# This section compiles all analyses into a single PDF report.
#
# PDF STRUCTURE:
#
# PAGE 1: OVERALL SUMMARY
#   - Headline underpayment statistics and wage premium
#
# PAGES 2-3: SCATTERPLOTS
#   - Page 2: Salary vs wage premium (all data, blue dots)
#   - Page 3: Salary vs wage premium colored by 2021 Rule eligibility (green/red)
#
# PAGES 4-20: ELIGIBLE POPULATION ANALYSES
#   These show characteristics of workers who can apply under each policy
#   - Pages 4-6: Underpayment rates by age (cohorts and 5-year groups)
#   - Pages 7-12: Policy comparison (underpayment rates, wage premiums, by $/%)
#   - Pages 13-14: Salary trends by year and policy (median and mean)
#   - Pages 15-16: Salary comparison tables (Status Quo vs Experience Benchmarking)
#   - Page 17: Underpayment by prior visa status (top 5)
#   - Page 18: **NEW** Underpayment F-1 vs All Others
#   - Pages 19-20: Age distribution and PhD share by policy
#
# PAGES 21-28: WEIGHTED LOTTERY SIMULATION ANALYSES
#   These show characteristics of workers who would be selected under weighted lottery
#   (simulation where higher-paid workers get more lottery entries)
#   - Pages 21-22: Salary trends by year (median and mean, weighted)
#   - Page 23: Age distribution (weighted)
#   - Pages 24-25: Wage premium by year ($/%, weighted)
#   - Pages 26-27: PhD share and F-1 status share (weighted)
#   - Page 28: Underpayment share (weighted)
#
# PAGES 29-34: INDUSTRY AND OCCUPATION COMPOSITION
#   - Page 29: Underpayment rates by top 10 industries
#   - Page 30: Underpayment rates by top 10 occupations
#   - Page 31: Industry mix by policy (eligible population)
#   - Page 32: Industry mix by policy (weighted lottery)
#   - Page 33: Occupation mix by policy (eligible population)
#   - Page 34: Occupation mix by policy (weighted lottery)
#
# PAGES 35-40: LIFETIME EARNINGS ANALYSES
#   Using NPV multipliers from Script 09 to estimate total career value
#   - Pages 35-37: Eligible population (median/mean at 3%, median at 7%)
#   - Pages 38-40: Weighted lottery (median/mean at 3%, median at 7%)
#
# PAGES 41-44: POLICY COMPARISON BY INDUSTRY/OCCUPATION
#   - Page 41: Underpayment rates by industry across policies (eligible)
#   - Page 42: Underpayment rates by industry across policies (weighted lottery)
#   - Page 43: Underpayment rates by occupation across policies (eligible)
#   - Page 44: Underpayment rates by occupation across policies (weighted lottery)
#
# PDF FORMAT:
# - Landscape orientation (11" × 8.5")
# - IFP brand colors and styling throughout
# - Each page is self-contained with title and subtitle
#
# USAGE:
# Open output/analysis/economic_analysis.pdf to review all analyses
################################################################################

cat("\n=== Exporting PDF ===\n")

pdf("output/analysis/economic_analysis.pdf", width = 11, height = 8.5)  # Landscape orientation

# Page 1: Overall stats
print(p1)

# Page 2: Scatterplot
print(p2)

# Page 3: Scatterplot colored by 2021 Rule eligibility
print(p2a)

# Page 4: Underpayment by age cohort (20-29, 30-39, 40-49, 50-59)
print(p3)

# Page 5: Underpayment by 5-year age group
print(p4)

# Page 6: Premium by 5-year age group
print(p5)

# Page 7: Policy comparison bar chart
print(p6)

# Page 8: Policy comparison table
print(p7)

# Page 9: Median underpayment ($) among underpaid by policy
print(p8)

# Page 10: Median underpayment (%) among underpaid by policy
print(p9)

# Page 11: Median wage premium ($) among eligible by policy
print(p10)

# Page 12: Median wage premium (%) among eligible by policy
print(p11)

# Page 13: Median salary by year and policy
print(p12)

# Page 14: Mean salary by year and policy
print(p13)

# Page 15: Median salary comparison (Status Quo vs Experience Benchmarking)
grid::grid.newpage()
grid::grid.draw(p13a)
title_grob <- grid::textGrob("Median Salary Comparison: Status Quo vs Experience Benchmarking",
                             y = 0.95, gp = grid::gpar(fontsize = 16, fontface = "bold"))
grid::grid.draw(title_grob)

# Page 16: Mean salary comparison (Status Quo vs Experience Benchmarking)
grid::grid.newpage()
grid::grid.draw(p13b)
title_grob <- grid::textGrob("Mean Salary Comparison: Status Quo vs Experience Benchmarking",
                             y = 0.95, gp = grid::gpar(fontsize = 16, fontface = "bold"))
grid::grid.draw(title_grob)

# Page 17: Underpayment by prior visa status (top 5)
print(p13c)

# Page 18: Underpayment F-1 vs All Others
print(p13d)

# Page 19: Eligible population - age distribution by policy
print(p14)

# Page 20: Eligible population - PhD share by policy
print(p15)

# Page 21: Weighted lottery - median salary by year
print(p16)

# Page 22: Weighted lottery - mean salary by year
print(p17)

# Page 23: Weighted lottery - age distribution
print(p18)

# Page 24: Weighted lottery - median wage premium ($) by year
print(p19)

# Page 25: Weighted lottery - median wage premium (%) by year
print(p20)

# Page 26: Weighted lottery - PhD share
print(p21)

# Page 27: Weighted lottery - share with prior F-1 status
print(p22)

# Page 28: Weighted lottery - share underpaid
print(p23)

# Page 29: Underpayment by top 10 industries (eligible population)
print(p24)

# Page 30: Underpayment by top 10 occupations (eligible population)
print(p25)

# Page 31: Industry mix - eligible population
print(p26)

# Page 32: Industry mix - weighted lottery
print(p27)

# Page 33: Occupation mix - eligible population
print(p28)

# Page 34: Occupation mix - weighted lottery
print(p29)

# Page 35: Median lifetime earnings - eligible population (3% discount)
print(p30)

# Page 36: Mean lifetime earnings - eligible population (3% discount)
print(p31)

# Page 37: Median lifetime earnings - eligible population (7% discount)
print(p32)

# Page 38: Median lifetime earnings - weighted lottery (3% discount)
print(p33)

# Page 39: Mean lifetime earnings - weighted lottery (3% discount)
print(p34)

# Page 40: Median lifetime earnings - weighted lottery (7% discount)
print(p35)

# Page 41: Underpayment by industry - eligible population (policy comparison)
print(p36)

# Page 42: Underpayment by industry - weighted lottery (policy comparison)
print(p37)

# Page 43: Underpayment by occupation - eligible population (policy comparison)
print(p38)

# Page 44: Underpayment by occupation - weighted lottery (policy comparison)
print(p39)

################################################################################
# NEW ANALYSES: FIRM TYPE AND EDUCATION LEVEL
#
# This section adds analyses requested for the launch paper:
# 1. Underpayment rate among H-1B dependent firms
# 2. Share of petitions to H-1B dependent firms by policy
# 3. Share of petitions to IT outsourcers by policy
# 4. Share of underpaid petitions: IT outsourcers vs others
# 5. Median underpayment by firm type
# 6. Eligibility rates by firm type and policy
# 7. Underpayment and wage premium by education level
# 8. Underpayment by education and firm type
################################################################################

cat("\n=== NEW ANALYSES: Firm Type and Education Level ===\n")

################################################################################
# ANALYSIS 1: Underpayment Rate Among H-1B Dependent Firms
################################################################################

cat("\n--- Analysis 1: H-1B Dependent Firms Underpayment ---\n")

h1b_dependent_stats <- h1b_policy %>%
  filter(is_h1b_dependent) %>%
  summarise(
    n = n(),
    n_underpaid = sum(underpaid, na.rm = TRUE),
    pct_underpaid = 100 * mean(underpaid, na.rm = TRUE),
    median_wage_premium = median(wage_premium_pct, na.rm = TRUE)
  )

cat(sprintf("H-1B Dependent Firms:\n"))
cat(sprintf("  Total petitions: %s\n", format(h1b_dependent_stats$n, big.mark = ",")))
cat(sprintf("  Underpaid: %s (%.1f%%)\n",
            format(h1b_dependent_stats$n_underpaid, big.mark = ","),
            h1b_dependent_stats$pct_underpaid))
cat(sprintf("  Median wage premium: %.1f%%\n", h1b_dependent_stats$median_wage_premium))

# Create bar chart with all three firm types
underpayment_by_firm_type <- h1b_policy %>%
  group_by(firm_type) %>%
  summarise(
    n = n(),
    n_underpaid = sum(underpaid, na.rm = TRUE),
    pct_underpaid = 100 * mean(underpaid, na.rm = TRUE),
    .groups = "drop"
  )

p40 <- ggplot(underpayment_by_firm_type, aes(x = firm_type, y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Underpayment Rate by Firm Type",
    subtitle = "Percentage of workers paid less than similarly-qualified Americans",
    x = NULL,
    y = "Underpaid (%)"
  ) +
  theme_ifp()

################################################################################
# ANALYSIS 2 & 3: Share of Petitions by Policy
# (H-1B Dependent Firms and IT Outsourcers)
################################################################################

cat("\n--- Analysis 2 & 3: Share of Petitions by Policy ---\n")

# Calculate share of petitions going to each firm type under each policy
policy_firm_shares <- tibble(
  policy = factor(rep(c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"), 3),
                  levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking")),
  firm_type = rep(c("IT Outsourcer", "H-1B Dependent", "Other"), each = 4)
) %>%
  mutate(
    n_eligible = c(
      # IT Outsourcers
      sum(h1b_policy$eligible_status_quo & h1b_policy$firm_type == "IT Outsourcer", na.rm = TRUE),
      sum(h1b_policy$eligible_2021 & h1b_policy$firm_type == "IT Outsourcer", na.rm = TRUE),
      sum(h1b_policy$eligible_p50 & h1b_policy$firm_type == "IT Outsourcer", na.rm = TRUE),
      sum(h1b_policy$eligible_eb & h1b_policy$firm_type == "IT Outsourcer", na.rm = TRUE),
      # H-1B Dependent
      sum(h1b_policy$eligible_status_quo & h1b_policy$firm_type == "H-1B Dependent", na.rm = TRUE),
      sum(h1b_policy$eligible_2021 & h1b_policy$firm_type == "H-1B Dependent", na.rm = TRUE),
      sum(h1b_policy$eligible_p50 & h1b_policy$firm_type == "H-1B Dependent", na.rm = TRUE),
      sum(h1b_policy$eligible_eb & h1b_policy$firm_type == "H-1B Dependent", na.rm = TRUE),
      # Other
      sum(h1b_policy$eligible_status_quo & h1b_policy$firm_type == "Other", na.rm = TRUE),
      sum(h1b_policy$eligible_2021 & h1b_policy$firm_type == "Other", na.rm = TRUE),
      sum(h1b_policy$eligible_p50 & h1b_policy$firm_type == "Other", na.rm = TRUE),
      sum(h1b_policy$eligible_eb & h1b_policy$firm_type == "Other", na.rm = TRUE)
    )
  ) %>%
  group_by(policy) %>%
  mutate(
    total_eligible = sum(n_eligible),
    pct_share = 100 * n_eligible / total_eligible
  ) %>%
  ungroup()

print(policy_firm_shares)

# Stacked bar chart showing composition by firm type
p41 <- ggplot(policy_firm_shares, aes(x = policy, y = pct_share, fill = firm_type)) +
  geom_col(position = "stack") +
  scale_fill_manual(values = c("IT Outsourcer" = ifp_colors$red,
                               "H-1B Dependent" = ifp_colors$orange,
                               "Other" = ifp_colors$dark_blue)) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Eligible Petition Composition by Firm Type and Policy",
    subtitle = "Share of petitions going to each firm type (no weighted lottery)",
    x = NULL,
    y = "Share of Petitions (%)",
    fill = "Firm Type"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1),
        legend.position = "bottom")

# Individual charts for IT Outsourcers and H-1B Dependent
it_outsourcer_shares <- policy_firm_shares %>%
  filter(firm_type == "IT Outsourcer")

p42 <- ggplot(it_outsourcer_shares, aes(x = policy, y = pct_share)) +
  geom_col(fill = ifp_colors$red) +
  geom_text(aes(label = sprintf("%.1f%%", pct_share)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Share of Petitions to IT Outsourcers by Policy",
    subtitle = "Percentage of eligible petitions going to large IT outsourcing firms",
    x = NULL,
    y = "IT Outsourcer Share (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

h1b_dep_shares <- policy_firm_shares %>%
  filter(firm_type == "H-1B Dependent")

p43 <- ggplot(h1b_dep_shares, aes(x = policy, y = pct_share)) +
  geom_col(fill = ifp_colors$orange) +
  geom_text(aes(label = sprintf("%.1f%%", pct_share)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Share of Petitions to H-1B Dependent Firms by Policy",
    subtitle = "Percentage of eligible petitions going to H-1B dependent firms",
    x = NULL,
    y = "H-1B Dependent Share (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1))

################################################################################
# ANALYSIS 4: Share of Underpaid Petitions - IT Outsourcers vs Others
################################################################################

cat("\n--- Analysis 4: Underpaid Petitions by Firm Type ---\n")

underpaid_by_firm <- h1b_policy %>%
  filter(underpaid) %>%
  summarise(
    n_total = n(),
    n_it_outsourcer = sum(firm_type == "IT Outsourcer", na.rm = TRUE),
    n_h1b_dependent = sum(firm_type == "H-1B Dependent", na.rm = TRUE),
    n_other = sum(firm_type == "Other", na.rm = TRUE),
    pct_it_outsourcer = 100 * n_it_outsourcer / n_total,
    pct_h1b_dependent = 100 * n_h1b_dependent / n_total,
    pct_other = 100 * n_other / n_total
  )

cat(sprintf("Among underpaid petitions:\n"))
cat(sprintf("  IT Outsourcers: %s (%.1f%%)\n",
            format(underpaid_by_firm$n_it_outsourcer, big.mark = ","),
            underpaid_by_firm$pct_it_outsourcer))
cat(sprintf("  H-1B Dependent: %s (%.1f%%)\n",
            format(underpaid_by_firm$n_h1b_dependent, big.mark = ","),
            underpaid_by_firm$pct_h1b_dependent))
cat(sprintf("  Other: %s (%.1f%%)\n",
            format(underpaid_by_firm$n_other, big.mark = ","),
            underpaid_by_firm$pct_other))

p44 <- ggplot(data.frame(
  firm_type = factor(c("IT Outsourcer", "H-1B Dependent", "Other"),
                    levels = c("IT Outsourcer", "H-1B Dependent", "Other")),
  pct_share = c(underpaid_by_firm$pct_it_outsourcer,
                underpaid_by_firm$pct_h1b_dependent,
                underpaid_by_firm$pct_other)
), aes(x = firm_type, y = pct_share)) +
  geom_col(fill = ifp_colors$red) +
  geom_text(aes(label = sprintf("%.1f%%", pct_share)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Composition of Underpaid Petitions by Firm Type",
    subtitle = "Share of all underpaid petitions at each firm type",
    x = NULL,
    y = "Share of Underpaid Petitions (%)"
  ) +
  theme_ifp()

################################################################################
# ANALYSIS 4B: Underpayment Rate - H-1B Dependent vs All Other
################################################################################

cat("\n--- Analysis 4B: Underpayment Rate - H-1B Dependent vs All Other ---\n")

underpayment_rate_h1b_vs_other <- h1b_policy %>%
  mutate(
    firm_category = case_when(
      is_h1b_dependent == TRUE ~ "H-1B Dependent",
      TRUE ~ "All Other"
    )
  ) %>%
  group_by(firm_category) %>%
  summarise(
    n_total = n(),
    n_underpaid = sum(underpaid, na.rm = TRUE),
    pct_underpaid = 100 * n_underpaid / n_total,
    .groups = "drop"
  )

print(underpayment_rate_h1b_vs_other)

p44b <- ggplot(underpayment_rate_h1b_vs_other, aes(x = firm_category, y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            vjust = -0.5, size = 4, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Underpayment Rate: H-1B Dependent vs All Other Firms",
    subtitle = "Percentage of workers paid less than similarly-qualified Americans",
    x = NULL,
    y = "Underpaid (%)"
  ) +
  theme_ifp()

################################################################################
# ANALYSIS 5: Median Wage Premium by Firm Type (All Petitions)
# H-1B Dependent vs All Other
################################################################################

cat("\n--- Analysis 5: Median Wage Premium by Firm Type ---\n")

median_premium_by_firm <- h1b_policy %>%
  mutate(
    firm_category = case_when(
      is_h1b_dependent == TRUE ~ "H-1B Dependent",
      TRUE ~ "All Other"  # Includes FALSE and NA
    )
  ) %>%
  group_by(firm_category) %>%
  summarise(
    n = n(),
    median_premium_dollars = median(petition_annual_pay_clean - pw_p50, na.rm = TRUE),
    median_premium_pct = median(wage_premium_pct, na.rm = TRUE),
    .groups = "drop"
  )

print(median_premium_by_firm)

p45 <- ggplot(median_premium_by_firm, aes(x = firm_category, y = median_premium_dollars)) +
  geom_col(aes(fill = median_premium_dollars >= 0)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black) +
  geom_text(aes(label = dollar(median_premium_dollars, accuracy = 1)),
            vjust = ifelse(median_premium_by_firm$median_premium_dollars >= 0, -0.5, 1.5),
            size = 4, color = ifp_colors$rich_black) +
  scale_fill_manual(values = c("TRUE" = ifp_colors$green, "FALSE" = ifp_colors$red), guide = "none") +
  scale_y_continuous(labels = dollar_format(),
                     expand = expansion(mult = c(0.15, 0.15))) +
  labs(
    title = "Median Wage Premium by Firm Type (All Petitions)",
    subtitle = "Median dollar difference relative to similarly-qualified Americans (negative = underpaid)",
    x = NULL,
    y = "Median Wage Premium ($)"
  ) +
  theme_ifp()

p46 <- ggplot(median_premium_by_firm, aes(x = firm_category, y = median_premium_pct)) +
  geom_col(aes(fill = median_premium_pct >= 0)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black) +
  geom_text(aes(label = sprintf("%.1f%%", median_premium_pct)),
            vjust = ifelse(median_premium_by_firm$median_premium_pct >= 0, -0.5, 1.5),
            size = 4, color = ifp_colors$rich_black) +
  scale_fill_manual(values = c("TRUE" = ifp_colors$green, "FALSE" = ifp_colors$red), guide = "none") +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0.15, 0.15))) +
  labs(
    title = "Median Wage Premium (%) by Firm Type (All Petitions)",
    subtitle = "Median percentage difference relative to similarly-qualified Americans (negative = underpaid)",
    x = NULL,
    y = "Median Wage Premium (%)"
  ) +
  theme_ifp()

################################################################################
# ANALYSIS 6: Eligibility Rates by Firm Type and Policy
################################################################################

cat("\n--- Analysis 6: Eligibility by Firm Type and Policy ---\n")

eligibility_by_firm_policy <- h1b_policy %>%
  group_by(firm_type) %>%
  summarise(
    n_total = n(),
    # Status Quo
    n_eligible_sq = sum(eligible_status_quo, na.rm = TRUE),
    pct_eligible_sq = 100 * n_eligible_sq / n_total,
    # 2021 Rule
    n_eligible_2021 = sum(eligible_2021, na.rm = TRUE),
    pct_eligible_2021 = 100 * n_eligible_2021 / n_total,
    # 50th Percentile
    n_eligible_p50 = sum(eligible_p50, na.rm = TRUE),
    pct_eligible_p50 = 100 * n_eligible_p50 / n_total,
    # Experience Benchmarking
    n_eligible_eb = sum(eligible_eb, na.rm = TRUE),
    pct_eligible_eb = 100 * n_eligible_eb / n_total,
    .groups = "drop"
  )

# Reshape for plotting
eligibility_long <- eligibility_by_firm_policy %>%
  select(firm_type, pct_eligible_sq, pct_eligible_2021, pct_eligible_p50, pct_eligible_eb) %>%
  pivot_longer(cols = starts_with("pct_"),
               names_to = "policy",
               values_to = "pct_eligible") %>%
  mutate(
    policy = factor(case_when(
      policy == "pct_eligible_sq" ~ "Status Quo",
      policy == "pct_eligible_2021" ~ "2021 Rule",
      policy == "pct_eligible_p50" ~ "50th Percentile Minimum",
      policy == "pct_eligible_eb" ~ "Experience Benchmarking"
    ), levels = c("Status Quo", "2021 Rule", "50th Percentile Minimum", "Experience Benchmarking"))
  )

print(eligibility_long)

p47 <- ggplot(eligibility_long, aes(x = policy, y = pct_eligible, fill = firm_type)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("IT Outsourcer" = ifp_colors$red,
                               "H-1B Dependent" = ifp_colors$orange,
                               "Other" = ifp_colors$dark_blue)) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Eligibility Rates by Firm Type and Policy",
    subtitle = "Percentage of petitions that meet each policy's wage threshold",
    x = NULL,
    y = "Eligible (%)",
    fill = "Firm Type"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 20, hjust = 1),
        legend.position = "bottom")

################################################################################
# ANALYSIS 7: Underpayment and Wage Premium by Education Level
################################################################################

cat("\n--- Analysis 7: Underpayment by Education Level ---\n")

# Calculate underpayment statistics by education (Bachelor's degree or higher only)
underpay_by_education <- h1b_policy %>%
  filter(!is.na(highest_ed),
         highest_ed %in% c("Bachelors", "Masters", "Prof degree", "PhD")) %>%
  group_by(highest_ed) %>%
  summarise(
    n = n(),
    n_underpaid = sum(underpaid, na.rm = TRUE),
    pct_underpaid = 100 * mean(underpaid, na.rm = TRUE),
    median_wage_premium = median(wage_premium_pct, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    highest_ed = factor(highest_ed,
                       levels = c("Bachelors", "Masters", "Prof degree", "PhD"))
  ) %>%
  arrange(highest_ed)

print(underpay_by_education)

p48 <- ggplot(underpay_by_education, aes(x = highest_ed, y = pct_underpaid)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = sprintf("%.1f%%", pct_underpaid)),
            vjust = -0.5, size = 3.5, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Underpayment Rate by Education Level",
    subtitle = "Percentage of workers paid less than similarly-qualified Americans",
    x = "Education Level",
    y = "Underpaid (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 35, hjust = 1))

p49 <- ggplot(underpay_by_education, aes(x = highest_ed, y = median_wage_premium)) +
  geom_col(fill = ifp_colors$purple) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black) +
  geom_text(aes(label = sprintf("%.1f%%", median_wage_premium)),
            vjust = ifelse(underpay_by_education$median_wage_premium >= 0, -0.5, 1.5),
            size = 3.5, color = ifp_colors$rich_black) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0.15, 0.15))) +
  labs(
    title = "Median Wage Premium by Education Level",
    subtitle = "Median percentage above/below similarly-qualified Americans (negative = underpaid)",
    x = "Education Level",
    y = "Median Wage Premium (%)"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 35, hjust = 1))

################################################################################
# ANALYSIS 8: Underpayment by Education Level and Firm Type
################################################################################

cat("\n--- Analysis 8: Underpayment by Education and Firm Type ---\n")

underpay_by_ed_firm <- h1b_policy %>%
  filter(!is.na(highest_ed),
         highest_ed %in% c("Bachelors", "Masters", "Prof degree", "PhD")) %>%
  group_by(highest_ed, firm_type) %>%
  summarise(
    n = n(),
    n_underpaid = sum(underpaid, na.rm = TRUE),
    pct_underpaid = 100 * mean(underpaid, na.rm = TRUE),
    median_wage_premium = median(wage_premium_pct, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    highest_ed = factor(highest_ed,
                       levels = c("Bachelors", "Masters", "Prof degree", "PhD"))
  )

print(underpay_by_ed_firm)

p50 <- ggplot(underpay_by_ed_firm, aes(x = highest_ed, y = pct_underpaid, fill = firm_type)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("IT Outsourcer" = ifp_colors$red,
                               "H-1B Dependent" = ifp_colors$orange,
                               "Other" = ifp_colors$dark_blue)) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "Underpayment Rate by Education Level and Firm Type",
    subtitle = "Percentage of workers paid less than similarly-qualified Americans",
    x = "Education Level",
    y = "Underpaid (%)",
    fill = "Firm Type"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 35, hjust = 1),
        legend.position = "bottom")

p51 <- ggplot(underpay_by_ed_firm, aes(x = highest_ed, y = median_wage_premium, fill = firm_type)) +
  geom_col(position = "dodge") +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black) +
  scale_fill_manual(values = c("IT Outsourcer" = ifp_colors$red,
                               "H-1B Dependent" = ifp_colors$orange,
                               "Other" = ifp_colors$dark_blue)) +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0.15, 0.15))) +
  labs(
    title = "Median Wage Premium by Education Level and Firm Type",
    subtitle = "Median percentage above/below similarly-qualified Americans",
    x = "Education Level",
    y = "Median Wage Premium (%)",
    fill = "Firm Type"
  ) +
  theme_ifp() +
  theme(axis.text.x = element_text(angle = 35, hjust = 1),
        legend.position = "bottom")

################################################################################
# ANALYSIS 9: Median Wage Premium by Top Industries and Occupations
################################################################################

cat("\n--- Analysis 9: Median Wage Premium by Top Industries and Occupations ---\n")

# Top 10 industries by petition count
top_industries_for_premium <- h1b_policy %>%
  filter(eligible_status_quo, !is.na(petition_employer_naics)) %>%
  dplyr::count(petition_employer_naics, sort = TRUE) %>%
  head(10) %>%
  pull(petition_employer_naics)

# Calculate median wage premium by industry
premium_by_industry <- h1b_policy %>%
  filter(petition_employer_naics %in% top_industries_for_premium) %>%
  mutate(
    industry_label = case_when(
      petition_employer_naics == "541511" ~ "Custom Computer\nProgramming",
      petition_employer_naics == "541512" ~ "Computer Systems\nDesign",
      petition_employer_naics == "511210" ~ "Software\nPublishers",
      petition_employer_naics == "54151" ~ "Computer Systems\nDesign (54151)",
      petition_employer_naics == "45411" ~ "Electronic\nShopping",
      petition_employer_naics == "518210" ~ "Data Processing/\nHosting",
      petition_employer_naics == "541330" ~ "Engineering\nServices",
      petition_employer_naics == "541519" ~ "Other Computer\nServices",
      petition_employer_naics == "999999" ~ "Unknown/\nNot Specified",
      petition_employer_naics == "523110" ~ "Investment\nBanking",
      TRUE ~ paste0("NAICS ", petition_employer_naics)
    )
  ) %>%
  group_by(industry_label) %>%
  summarise(
    n = n(),
    median_premium_pct = median(wage_premium_pct, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(n))

print(premium_by_industry)

p52 <- ggplot(premium_by_industry, aes(x = reorder(industry_label, median_premium_pct), y = median_premium_pct)) +
  geom_col(aes(fill = median_premium_pct >= 0)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black) +
  coord_flip() +
  scale_fill_manual(values = c("TRUE" = ifp_colors$green, "FALSE" = ifp_colors$red), guide = "none") +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0.1, 0.1))) +
  labs(
    title = "Median Wage Premium by Top 10 Industries",
    subtitle = "Median percentage above/below similarly-qualified Americans (negative = underpaid)",
    x = NULL,
    y = "Median Wage Premium (%)"
  ) +
  theme_ifp()

# Top 10 occupations by petition count
top_occupations_for_premium <- h1b_policy %>%
  filter(eligible_status_quo, !is.na(SOC_TITLE)) %>%
  dplyr::count(SOC_TITLE, sort = TRUE) %>%
  head(10) %>%
  pull(SOC_TITLE)

# Calculate median wage premium by occupation
premium_by_occupation <- h1b_policy %>%
  filter(SOC_TITLE %in% top_occupations_for_premium) %>%
  mutate(
    occupation_label = case_when(
      grepl("Software Developers", SOC_TITLE) ~ "Software Developers",
      grepl("Computer Systems Analysts", SOC_TITLE) ~ "Computer Systems\nAnalysts",
      grepl("Computer Systems Engineers", SOC_TITLE) ~ "Computer Systems\nEngineers/Architects",
      grepl("Computer Programmers", SOC_TITLE) ~ "Computer Programmers",
      grepl("Software Quality", SOC_TITLE) ~ "Software QA\nAnalysts/Testers",
      grepl("Information Technology Project", SOC_TITLE) ~ "IT Project Managers",
      grepl("Computer Occupations, All Other", SOC_TITLE) ~ "Computer\nOccupations (Other)",
      grepl("Business Intelligence", SOC_TITLE) ~ "Business Intelligence\nAnalysts",
      grepl("Mechanical Engineers", SOC_TITLE) ~ "Mechanical Engineers",
      grepl("Operations Research", SOC_TITLE) ~ "Operations Research\nAnalysts",
      TRUE ~ SOC_TITLE
    )
  ) %>%
  group_by(occupation_label) %>%
  summarise(
    n = n(),
    median_premium_pct = median(wage_premium_pct, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(n))

print(premium_by_occupation)

p53 <- ggplot(premium_by_occupation, aes(x = reorder(occupation_label, median_premium_pct), y = median_premium_pct)) +
  geom_col(aes(fill = median_premium_pct >= 0)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black) +
  coord_flip() +
  scale_fill_manual(values = c("TRUE" = ifp_colors$green, "FALSE" = ifp_colors$red), guide = "none") +
  scale_y_continuous(labels = label_percent(scale = 1),
                     expand = expansion(mult = c(0.1, 0.1))) +
  labs(
    title = "Median Wage Premium by Top 10 Occupations",
    subtitle = "Median percentage above/below similarly-qualified Americans (negative = underpaid)",
    x = NULL,
    y = "Median Wage Premium (%)"
  ) +
  theme_ifp()

################################################################################
# Print all new pages to PDF
################################################################################

# Page 45: H-1B Dependent underpayment comparison
print(p40)

# Page 46: Petition composition by firm type and policy (stacked)
print(p41)

# Page 47: IT Outsourcer share by policy
print(p42)

# Page 48: H-1B Dependent share by policy
print(p43)

# Page 49: Underpaid petition composition by firm type
print(p44)

# Page 50: Share underpaid - H-1B dependent vs all other
print(p44b)

# Page 51: Median wage premium ($) by firm type
print(p45)

# Page 52: Median wage premium (%) by firm type
print(p46)

# Page 53: Eligibility rates by firm type and policy
print(p47)

# Page 54: Underpayment rate by education level
print(p48)

# Page 55: Median wage premium by education level
print(p49)

# Page 56: Underpayment rate by education and firm type
print(p50)

# Page 57: Median wage premium by education and firm type
print(p51)

# Page 58: Median wage premium by top 10 industries
print(p52)

# Page 59: Median wage premium by top 10 occupations
print(p53)

dev.off()

cat("\n=== Analysis Complete ===\n")
cat("Output saved to: output/analysis/economic_analysis.pdf\n")
cat("Total pages: 59\n")
cat("\nPage 1: Overall Summary\n")
cat("Pages 2-3: Scatterplots (Salary vs Wage Premium)\n")
cat("Pages 4-20: Eligible Population Analyses\n")
cat("  Pages 15-16: Salary Comparison Tables (Status Quo vs Experience Benchmarking)\n")
cat("  Page 17: Underpayment by Prior Visa Status (Top 5)\n")
cat("  Page 18: Underpayment F-1 vs All Others\n")
cat("Pages 21-28: Weighted Lottery Simulation Analyses\n")
cat("Pages 29-34: Industry and Occupation Analyses\n")
cat("Pages 35-40: Lifetime Earnings Analyses\n")
cat("Pages 41-44: Underpayment by Industry/Occupation (Policy Comparisons)\n")
cat("Pages 45-59: Firm Type and Education Level Analyses\n")
cat("  Page 45: Underpayment Rate by Firm Type (3 bars)\n")
cat("  Page 46: Petition Composition by Firm Type and Policy\n")
cat("  Page 47: IT Outsourcer Share by Policy\n")
cat("  Page 48: H-1B Dependent Share by Policy\n")
cat("  Page 49: Underpaid Petition Composition by Firm Type (3 bars)\n")
cat("  Page 50: Underpayment Rate - H-1B Dependent vs All Other (2 bars)\n")
cat("  Page 51: Median Wage Premium ($) - H-1B Dependent vs All Other\n")
cat("  Page 52: Median Wage Premium (%) - H-1B Dependent vs All Other\n")
cat("  Page 53: Eligibility Rates by Firm Type and Policy\n")
cat("  Page 54: Underpayment Rate by Education Level (Bachelor's+)\n")
cat("  Page 55: Median Wage Premium by Education Level (Bachelor's+)\n")
cat("  Page 56: Underpayment by Education and Firm Type (Bachelor's+)\n")
cat("  Page 57: Wage Premium by Education and Firm Type (Bachelor's+)\n")
cat("  Page 58: Median Wage Premium by Top 10 Industries\n")
cat("  Page 59: Median Wage Premium by Top 10 Occupations\n")
