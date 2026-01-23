# H-1B Wage Premium Analysis
# Standalone R script for interactive exploration
# Created: 2026-01-15
# Updated: 2026-01-23 to add PUMA controls

# =============================================================================
# 1. Setup and Helper Functions
# =============================================================================

# Load configuration
# Check if we're in the scripts directory or project root
if (file.exists("../config.R")) {
  source("../config.R")  # Running from scripts/
} else if (file.exists("config.R")) {
  source("config.R")      # Running from project root
} else {
  stop("Cannot find config.R. Please run from project root or scripts/ directory")
}

library(ipumsr)
library(tidyverse)
library(readxl)
library(scales)
library(matrixStats)

# --- Education Code Mapping ---
map_education_code <- function(code) {
  case_when(
    code == "A" ~ 1L,    # Less than high school
    code == "B" ~ 63L,   # High school diploma
    code == "C" ~ 65L,   # Some college
    code == "D" ~ 71L,   # Associate's degree
    code == "E" ~ 81L,   # Bachelor's degree
    code == "F" ~ 101L,  # Master's degree
    code == "G" ~ 114L,  # Professional degree (JD, MD)
    code == "H" ~ 115L,  # Doctorate
    code == "I" ~ 116L,  # Doctorate (alternate code)
    TRUE ~ 0L            # Unknown/missing
  )
}

# --- Plotting Utilities ---
# IFP Brand Color Palette (from IFP_style2024.css)
ifp_colors <- list(
  # Primary Colors
  off_white   = "#fcfbeb",
  purple      = "#b17ada",
  orange      = "#ff9762",
 rich_black  = "#373737",
  # Category Colors
  green       = "#39d794",
  red         = "#ff6565",
  light_blue  = "#41c4fc",
  yellow      = "#fbdb36",
  pink        = "#ff9ee3",
  dark_blue   = "#3368ce"   # Immigration - PRIMARY for this analysis
)

# Color scales for sequential data (light to dark blue)
ifp_blue_scale <- c("#a8d4f0", "#6bb3e0", "#41c4fc", "#3368ce", "#1a3d7a")

# Color scale for categorical comparisons (e.g., Yes/No, dependent/non-dependent)
ifp_binary_colors <- c("Y" = ifp_colors$dark_blue, "N" = ifp_colors$orange)

# Color scale for DOL Wage Levels (I, II, III, IV)
ifp_wage_level_colors <- c(
  "I"   = ifp_colors$light_blue,
  "II"  = ifp_colors$purple,
  "III" = ifp_colors$dark_blue,
  "IV"  = ifp_colors$rich_black
)

# Age group labels for x-axes
age_labels <- c(
 "[20,25)" = "20-24", "[25,30)" = "25-29", "[30,35)" = "30-34",
 "[35,40)" = "35-39", "[40,45)" = "40-44", "[45,50)" = "45-49",
 "[50,55)" = "50-54", "[55,60)" = "55-59", "[60,65)" = "60-64"
)

# Consistent theme across all plots (IFP-styled)
theme_h1b <- function() {
 theme_minimal() +
   theme(
     text = element_text(color = ifp_colors$rich_black),
     axis.text.x = element_text(angle = 30, hjust = 1, color = ifp_colors$rich_black),
     axis.text.y = element_text(color = ifp_colors$rich_black),
     axis.title = element_text(color = ifp_colors$rich_black),
     plot.caption = element_text(hjust = 0, margin = margin(t = 8), color = ifp_colors$rich_black),
     plot.title = element_text(size = 12, face = "bold", color = ifp_colors$rich_black),
     plot.subtitle = element_text(color = ifp_colors$rich_black),
     panel.grid.minor = element_blank(),
     legend.text = element_text(color = ifp_colors$rich_black),
     legend.title = element_text(color = ifp_colors$rich_black)
   )
}

# --- Premium Calculation Functions ---
# Calculate share with positive premium, grouped by specified variables
calc_share_positive <- function(data, ...) {
  data %>%
    filter(!is.na(Native), H1B == 1) %>%
    mutate(
      personal_premium = INCWAGE - Native,
      pos_neg = ifelse(personal_premium > 0, "Positive", "Negative")
    ) %>%
    group_by(..., pos_neg) %>%
    summarise(n = sum(H1B), .groups = "drop") %>%
    pivot_wider(names_from = pos_neg, values_from = n) %>%
    mutate(
      Positive = replace_na(Positive, 0),
      Negative = replace_na(Negative, 0),
      share_positive = Positive / (Positive + Negative),
      Total = Positive + Negative
    )
}

# Calculate average premium, grouped by specified variables
calc_avg_premium <- function(data, ...) {
  data %>%
    filter(!is.na(Native), H1B == 1, AGE < 65) %>%
    mutate(personal_premium = INCWAGE - Native) %>%
    group_by(...) %>%
    summarise(avg_premium = mean(personal_premium, na.rm = TRUE), .groups = "drop")
}

# =============================================================================
# 2. Data Loading
# =============================================================================

# H-1B FOIA data with PUMA codes (output from geocoding step)
# FY year refers to the fiscal year of the lottery;
# actual employment begins in the prior calendar year
h1b_raw <- read.csv(h1b_with_pumas_file)

cat("H-1B records loaded:", nrow(h1b_raw), "\n")

# ACS microdata from IPUMS
# NOTE: Your ACS extract MUST include PUMA variable for the new control configuration
ddi <- read_ipums_ddi(acs_ddi_file)
acs_raw <- read_ipums_micro(ddi)

cat("ACS records loaded:", nrow(acs_raw), "\n")

# Check if PUMA is in ACS data
if (!"PUMA" %in% names(acs_raw)) {
  warning("PUMA variable not found in ACS data. The age_occ_ed_puma control will not work.")
  warning("Please re-download your ACS extract from IPUMS with PUMA included.")
}

# SOC occupation code definitions for labeling
soc_codes <- read_excel(soc_definitions_file, skip = 7) %>%
  mutate(soc_numeric = str_remove_all(`SOC Code`, "-") %>% as.numeric())

occ6_labels <- soc_codes %>%
  filter(`SOC Group` == "Detailed") %>%
  mutate(occ = str_sub(as.character(soc_numeric), 1, 6)) %>%
  select(occ, `SOC Title`)

# =============================================================================
# 3. Data Cleaning and Standardization
# =============================================================================

# Clean and standardize H-1B data
# IMPORTANT: Only filter on fields that are ALWAYS needed (AGE, INCWAGE)
# Don't drop H-1Bs for missing education or occupation - those are only needed
# for specific comparison levels and will be naturally excluded during merges
h1b <- h1b_raw %>%
  transmute(
    YEAR = registration_lottery_year,
    AGE = YEAR - registration_birth_year,
    OCCSOC = as.character(as.numeric(gsub("-", "", SOC_CODE))),  # Convert to char for consistency
    EDUCD = map_education_code(petition_beneficiary_edu_code),
    INCWAGE = petition_annual_pay_clean,
    h1b_dependent = petition_employer_h1b_dependent,
    wage_level = wage_level_combined,
    prior_visa = petition_beneficiary_classif,
    # Use 2010 PUMA for 2021-2023 ACS data (which uses 2010 PUMAs)
    PUMA = as.character(PUMA_2010),
    H1B = 1L,
    PERWT = 1  # H-1B records are unweighted
  ) %>%
  filter(!is.na(AGE), INCWAGE > 0,
         YEAR != 2021)  # Only require valid age and income

cat("H-1B records after cleaning:", nrow(h1b), "\n")
cat("  - With valid education code:", sum(h1b$EDUCD != 0), "\n")
cat("  - With valid occupation code:", sum(!is.na(h1b$OCCSOC)), "\n")

# Clean ACS data: native-born, employed, with valid income
natives <- acs_raw %>%
  filter(
    CITIZEN %in% c(0, 1),                              # Native-born citizens
    INCWAGE > 0 & !INCWAGE %in% c(999998, 999999),    # Valid income
    EMPSTAT == 1                                       # Employed
  ) %>%
  transmute(
    YEAR,
    AGE,
    OCCSOC = as.character(OCCSOC),                     # Convert to char for consistency
    # Collapse education codes: 64 -> 63 (both = HS grad), <63 -> 1 (less than HS)
    EDUCD = if_else(EDUCD == 64, 63L, if_else(EDUCD < 63, 1L, as.integer(EDUCD))),
    INCWAGE,
    h1b_dependent = NA_character_,
    wage_level = NA_character_,
    prior_visa = NA_character_,
    # PUMA variable (if available in ACS data)
    PUMA = if("PUMA" %in% names(acs_raw)) as.character(PUMA) else NA_character_,
    H1B = 0L,
    PERWT
  )

cat("Native-born ACS records after cleaning:", nrow(natives), "\n")

# --- Combine into Analysis Panel ---
panel <- bind_rows(h1b, natives) %>%
  filter(INCWAGE > 0) %>%  # Only require valid income (age already filtered)
  mutate(
    EDUCD = as.factor(EDUCD),
    OCCSOC = as.factor(OCCSOC),  # NA values become NA factor level
    OCC2 = substr(as.character(OCCSOC), 1, 2),  # 2-digit SOC (major group)
    OCC3 = substr(as.character(OCCSOC), 1, 3),  # 3-digit SOC (minor group)
    age_grp = cut(AGE,
                  breaks = c(20, 25, 30, 35, 40, 45, 50, 55, 60, 65, Inf),
                  right = FALSE, include.lowest = TRUE)
  )

cat("\nFinal panel size:", nrow(panel), "observations\n")
cat("  H-1B workers:", sum(panel$H1B == 1), "\n")
cat("  Native-born workers:", sum(panel$H1B == 0), "\n")

# Show how many H-1Bs have valid fields for each comparison level
h1b_panel <- panel %>% filter(H1B == 1)
cat("\nH-1B records available for each comparison level:\n")
cat("  Age only:", sum(!is.na(h1b_panel$age_grp)), "\n")
cat("  Age + Education:", sum(!is.na(h1b_panel$age_grp) & h1b_panel$EDUCD != "0"), "\n")
cat("  Age + Occupation:", sum(!is.na(h1b_panel$age_grp) & !is.na(h1b_panel$OCCSOC)), "\n")
cat("  Full (Age + Edu + Occ):", sum(!is.na(h1b_panel$age_grp) & h1b_panel$EDUCD != "0" & !is.na(h1b_panel$OCCSOC)), "\n")
cat("  Full + PUMA (Age + Edu + Occ + PUMA):", sum(!is.na(h1b_panel$age_grp) & h1b_panel$EDUCD != "0" & !is.na(h1b_panel$OCCSOC) & !is.na(h1b_panel$PUMA)), "\n")

# =============================================================================
# 4. Constructing Native Wage Benchmarks
# =============================================================================

# Helper function to calculate native wage medians
calc_native_median <- function(data, ...) {
  data %>%
    filter(H1B == 0) %>%  # Native-born only
    group_by(...) %>%
    summarise(Native = weightedMedian(INCWAGE, w = PERWT, na.rm = TRUE), .groups = "drop")
}

# Calculate benchmarks at each granularity level
native_median <- list(
  full = calc_native_median(panel, YEAR, EDUCD, OCCSOC, age_grp),
  occ_age = calc_native_median(panel, YEAR, OCCSOC, age_grp),
  age_only = calc_native_median(panel, YEAR, age_grp),
  ed_age = calc_native_median(panel, YEAR, EDUCD, age_grp),
  age_occ_ed_puma = calc_native_median(panel, YEAR, EDUCD, OCCSOC, age_grp, PUMA)  # NEW
)

# Show cell counts
cat("Benchmark cells:\n")
cat("  Full (year x education x occupation x age):", nrow(native_median$full), "\n")
cat("  Occupation + Age:", nrow(native_median$occ_age), "\n")
cat("  Age only:", nrow(native_median$age_only), "\n")
cat("  Full + PUMA (year x education x occupation x age x PUMA):", nrow(native_median$age_occ_ed_puma), "\n")

# --- Merge Benchmarks with H-1B Data ---
h1b_merged <- list(
  full = left_join(panel, native_median$full,
                   by = c("YEAR", "EDUCD", "OCCSOC", "age_grp")),
  occ_age = left_join(panel, native_median$occ_age,
                      by = c("YEAR", "OCCSOC", "age_grp")),
  age_only = left_join(panel, native_median$age_only,
                       by = c("YEAR", "age_grp")),
  ed_age = left_join(panel, native_median$ed_age,
                     by = c("YEAR", "EDUCD", "age_grp")),
  age_occ_ed_puma = left_join(panel, native_median$age_occ_ed_puma,
                              by = c("YEAR", "EDUCD", "OCCSOC", "age_grp", "PUMA"))  # NEW
)

# Check merge rates (share of H-1Bs with a valid benchmark)
cat("\nMerge rates (% of H-1Bs matched to benchmark):\n")
for (nm in names(h1b_merged)) {
  rate <- h1b_merged[[nm]] %>%
    filter(H1B == 1) %>%
    summarise(pct = mean(!is.na(Native)) * 100) %>%
    pull(pct)
  cat(sprintf("  %s: %.1f%%\n", nm, rate))
}

# =============================================================================
# 5. Results: Basic Comparisons by Age
# =============================================================================

# --- Share with Positive Premium (Age Only) ---
premium_age_only <- h1b_merged$age_only %>%
  calc_share_positive(age_grp) %>%
  filter(!is.na(age_grp), age_grp != "[65,Inf]")

ggplot(premium_age_only, aes(x = age_grp, y = share_positive)) +
  geom_col(width = 0.8, fill = ifp_colors$light_blue) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)), vjust = -0.4, size = 3.5) +
  scale_y_continuous(labels = percent, limits = c(0, 1), expand = expansion(mult = c(0, 0.08))) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "H-1B Pay vs. Median Native in Same Age Group (Age Only)",
    subtitle = "No controls for occupation or education",
    x = "Age of H-1B recipient",
    y = "Share earning more than comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# --- Average Premium (Age Only) ---
avg_age_only <- h1b_merged$age_only %>%
  calc_avg_premium(age_grp) %>%
  filter(!is.na(age_grp), age_grp != "[65,Inf]")

ggplot(avg_age_only, aes(x = age_grp, y = avg_premium)) +
  geom_col(width = 0.8, fill = ifp_colors$light_blue) +
  geom_text(aes(
    label = paste0("$", round(avg_premium/1000), "k"),
    vjust = ifelse(avg_premium >= 0, -0.35, 1.15)
  ), size = 3) +
  scale_y_continuous(labels = dollar) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "Average H-1B Premium vs. Median Native in Same Age Group",
    subtitle = "No controls for occupation or education",
    x = "Age of H-1B recipient",
    y = "Average wage premium ($)",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# =============================================================================
# 6. Adding Education Controls
# =============================================================================

# --- Share with Positive Premium (Age + Education) ---
premium_ed_age <- h1b_merged$ed_age %>%
  calc_share_positive(age_grp) %>%
  filter(!is.na(age_grp), age_grp != "[65,Inf]")

ggplot(premium_ed_age, aes(x = age_grp, y = share_positive)) +
  geom_col(width = 0.8, fill = ifp_colors$orange) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)), vjust = -0.4, size = 3.5) +
  scale_y_continuous(labels = percent, limits = c(0, 1), expand = expansion(mult = c(0, 0.08))) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "H-1B Pay vs. Median Native in Same Age Group and Education Level",
    subtitle = "Controlling for education level (not occupation)",
    x = "Age of H-1B recipient",
    y = "Share earning more than comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# --- Average Premium (Age + Education) ---
avg_ed_age <- h1b_merged$ed_age %>%
  calc_avg_premium(age_grp) %>%
  filter(!is.na(age_grp), age_grp != "[65,Inf]")

ggplot(avg_ed_age, aes(x = age_grp, y = avg_premium)) +
  geom_col(width = 0.8, fill = ifp_colors$orange) +
  geom_text(aes(
    label = ifelse(avg_premium >= 0, paste0("$", round(avg_premium/1000), "k"),
                   paste0("-$", abs(round(avg_premium/1000)), "k")),
    vjust = ifelse(avg_premium >= 0, -0.35, 1.15)
  ), size = 3) +
  scale_y_continuous(labels = dollar) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "Average H-1B Premium vs. Median Native with Same Age and Education",
    subtitle = "Controlling for education level (not occupation)",
    x = "Age of H-1B recipient",
    y = "Average wage premium ($)",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# =============================================================================
# 7. Adding Occupation Controls
# =============================================================================

# --- Share with Positive Premium (Age + Occupation) ---
premium_occ_age <- h1b_merged$occ_age %>%
  calc_share_positive(age_grp) %>%
  filter(!is.na(age_grp), age_grp != "[65,Inf]")

ggplot(premium_occ_age, aes(x = age_grp, y = share_positive)) +
  geom_col(width = 0.8, fill = ifp_colors$purple) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)), vjust = -0.4, size = 3.5) +
  scale_y_continuous(labels = percent, limits = c(0, 1), expand = expansion(mult = c(0, 0.08))) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "H-1B Pay vs. Native in Same Age Group and Occupation",
    subtitle = "Controlling for 6-digit SOC occupation code",
    x = "Age of H-1B recipient",
    y = "Share earning more than comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# --- Average Premium (Age + Occupation) ---
avg_occ_age <- h1b_merged$occ_age %>%
  calc_avg_premium(age_grp) %>%
  filter(!is.na(age_grp), age_grp != "[65,Inf]")

ggplot(avg_occ_age, aes(x = age_grp, y = avg_premium)) +
  geom_col(width = 0.8, fill = ifp_colors$purple) +
  geom_text(aes(
    label = ifelse(avg_premium >= 0, paste0("$", round(avg_premium/1000), "k"),
                   paste0("-$", abs(round(avg_premium/1000)), "k")),
    vjust = ifelse(avg_premium >= 0, -0.35, 1.15)
  ), size = 3) +
  scale_y_continuous(labels = dollar) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "Average H-1B Premium vs. Median Native in Same Occupation and Age",
    x = "Age of H-1B recipient",
    y = "Average wage premium ($)",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# =============================================================================
# 8. Full Controls: Age, Occupation, and Education
# =============================================================================

# --- Share with Positive Premium (Full Controls) ---
premium_full <- h1b_merged$full %>%
  calc_share_positive(age_grp) %>%
  filter(!is.na(age_grp), age_grp != "[65,Inf]")

ggplot(premium_full, aes(x = age_grp, y = share_positive)) +
  geom_col(width = 0.8, fill = ifp_colors$dark_blue) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)), vjust = -0.4, size = 3.5) +
  scale_y_continuous(labels = percent, limits = c(0, 1), expand = expansion(mult = c(0, 0.08))) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "H-1B Pay vs. Native with Same Age, Occupation, and Education",
    subtitle = "Full controls: 5-year age bin + 6-digit SOC + education level",
    x = "Age of H-1B recipient",
    y = "Share earning more than comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# --- Average Premium (Full Controls) ---
avg_full <- h1b_merged$full %>%
  calc_avg_premium(age_grp) %>%
  filter(!is.na(age_grp), age_grp != "[65,Inf]")

ggplot(avg_full, aes(x = age_grp, y = avg_premium)) +
  geom_col(width = 0.8, fill = ifp_colors$dark_blue) +
  geom_text(aes(
    label = ifelse(avg_premium >= 0, paste0("$", round(avg_premium/1000), "k"),
                   paste0("-$", abs(round(avg_premium/1000)), "k")),
    vjust = ifelse(avg_premium >= 0, -0.35, 1.15)
  ), size = 3) +
  scale_y_continuous(labels = dollar) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "Average H-1B Premium with Full Controls",
    subtitle = "Compared to median native with same age, occupation, and education",
    x = "Age of H-1B recipient",
    y = "Average wage premium ($)",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# =============================================================================
# 9. Analysis by Prior Visa Status
# =============================================================================

prior_visa_data <- h1b_merged$full %>%
  filter(H1B == 1, !is.na(prior_visa), !is.na(age_grp), age_grp != "[65,Inf]") %>%
  mutate(change_of_status = ifelse(prior_visa == "", "N", "Y"))

prior_visa_share <- prior_visa_data %>%
  calc_share_positive(change_of_status, age_grp)

ggplot(prior_visa_share, aes(x = age_grp, y = share_positive, fill = change_of_status)) +
  geom_col(position = position_dodge(0.9), width = 0.8) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)),
            position = position_dodge(0.9), vjust = -0.4, size = 2.8) +
  scale_fill_manual(values = c("Y" = ifp_colors$dark_blue, "N" = ifp_colors$orange),
                    labels = c("Y" = "Yes (e.g., from F-1)", "N" = "No (direct from abroad)"),
                    name = "Adjusting from\nanother visa?") +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.08))) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "Share with Positive Premium by Prior Visa Status",
    subtitle = "Full controls: age, occupation, education",
    x = "Age of H-1B recipient",
    y = "Share earning more than comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# =============================================================================
# 10. Analysis by H-1B Dependent Employer Status
# =============================================================================

dependency_data <- h1b_merged$full %>%
  filter(H1B == 1, h1b_dependent %in% c("Y", "N"),
         !is.na(age_grp), age_grp != "[65,Inf]")

dependency_share <- dependency_data %>%
  calc_share_positive(h1b_dependent, age_grp)

ggplot(dependency_share, aes(x = age_grp, y = share_positive, fill = h1b_dependent)) +
  geom_col(position = position_dodge(0.9), width = 0.8) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)),
            position = position_dodge(0.9), vjust = -0.4, size = 2.8) +
  scale_fill_manual(values = c("Y" = ifp_colors$dark_blue, "N" = ifp_colors$orange),
                    labels = c("Y" = "Yes", "N" = "No"),
                    name = "H-1B dependent\nemployer?") +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.08))) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "Share with Positive Premium by H-1B Dependency Status",
    subtitle = "Full controls: age, occupation, education",
    x = "Age of H-1B recipient",
    y = "Share earning more than comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# --- Average Wage Premium by Dependency Status ---
dependency_avg_premium <- dependency_data %>%
  filter(!is.na(Native)) %>%
  mutate(personal_premium = INCWAGE - Native) %>%
  group_by(h1b_dependent, age_grp) %>%
  summarise(
    avg_premium = mean(personal_premium, na.rm = TRUE),
    n = n(),
    .groups = "drop"
  )

ggplot(dependency_avg_premium, aes(x = age_grp, y = avg_premium, fill = h1b_dependent)) +
  geom_col(position = position_dodge(0.9), width = 0.8) +
  geom_text(aes(label = dollar(avg_premium / 1000, accuracy = 1, suffix = "k")),
            position = position_dodge(0.9), vjust = -0.4, size = 2.8) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black, linewidth = 0.5) +
  scale_fill_manual(values = c("Y" = ifp_colors$dark_blue, "N" = ifp_colors$orange),
                    labels = c("Y" = "Yes", "N" = "No"),
                    name = "H-1B dependent\nemployer?") +
  scale_y_continuous(labels = dollar, expand = expansion(mult = c(0.05, 0.08))) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "Average Wage Premium by H-1B Dependency Status",
    subtitle = "Average wage premium for initial, cap-subject H-1Bs vs. median natives with the same occupation, age, and education level",
    x = "Age of H-1B recipient",
    y = "Average premium vs. comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# =============================================================================
# 11. Top H-1B Occupations
# =============================================================================

occ_premia <- h1b_merged$full %>%
  calc_share_positive(OCCSOC) %>%
  left_join(occ6_labels, by = c("OCCSOC" = "occ")) %>%
  filter(!is.na(`SOC Title`))

occ_premia %>%
  arrange(desc(Total)) %>%
  head(10) %>%
  ggplot(aes(x = reorder(str_wrap(`SOC Title`, 28), Total), y = share_positive)) +
  geom_col(fill = ifp_colors$dark_blue) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)), hjust = -0.1, size = 3.2) +
  geom_text(aes(label = paste0("n=", comma(Total)), y = 0.02), hjust = 0, size = 2.5, color = "white") +
  coord_flip() +
  scale_y_continuous(limits = c(0, 0.9), labels = percent) +
  labs(
    title = str_wrap("Share of Initial Cap-Subject H-1Bs Paid Higher than the Median Native of the Same Occupation, Age, and Education", width = 100),
    subtitle = str_wrap("Occupations ranked by total count of initial H-1Bs, FY2022-2024.", width = 100),
    x = NULL,
    y = "Share earning more than median wages of comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(size = 12, face = "bold"))

# --- Top Occupations Table ---
occ_premia %>%
  arrange(desc(Total)) %>%
  head(10) %>%
  mutate(
    Rank = row_number(),
    `Share Positive` = percent(share_positive, accuracy = 0.1),
    `Share Negative` = percent(1 - share_positive, accuracy = 0.1),
    Total = comma(Total)
  ) %>%
  select(Rank, `SOC Title`, Total, `Share Positive`, `Share Negative`) %>%
  knitr::kable(col.names = c("Rank", "Occupation", "N", "Share with Positive Premium", "Share with Negative Premium"))

# =============================================================================
# 12. Analysis by DOL Wage Level
# =============================================================================

wage_level_data <- h1b_merged$full %>%
  filter(H1B == 1, !is.na(wage_level), h1b_dependent %in% c("Y", "N"))

above_50th_share <- wage_level_data %>% filter(wage_level %in% c("III", "IV")) %>%
  calc_share_positive()

above_50th_share

# --- Share with Positive Premium by Wage Level (Overall) ---
wage_level_share_overall <- wage_level_data %>%
  calc_share_positive(wage_level)

ggplot(wage_level_share_overall, aes(x = wage_level, y = share_positive, fill = wage_level)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)), vjust = -0.4, size = 3.5) +
  scale_fill_manual(values = ifp_wage_level_colors) +
  scale_y_continuous(labels = percent, limits = c(0, 1), expand = expansion(mult = c(0, 0.08))) +
  labs(
    title = "Share of Initial H-1B Lottery Winners with Positive Premium by DOL Wage Level",
    subtitle = "Compared to median native with same age, occupation, and education",
    x = "DOL Wage Level",
    y = "Share earning more than comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b() +
  theme(legend.position = "none")

# --- Share with Positive Premium by Wage Level and H-1B Dependency ---
wage_level_share <- wage_level_data %>%
  calc_share_positive(wage_level, h1b_dependent)

ggplot(wage_level_share, aes(x = wage_level, y = share_positive, fill = h1b_dependent)) +
  geom_col(position = position_dodge(0.9), width = 0.8) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)),
            position = position_dodge(0.9), vjust = -0.4, size = 3) +
  scale_fill_manual(values = c("Y" = ifp_colors$dark_blue, "N" = ifp_colors$orange),
                    labels = c("Y" = "Yes", "N" = "No"),
                    name = "H-1B dependent?") +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.08))) +
  labs(
    title = "Share with Positive Premium by DOL Wage Level",
    subtitle = "Split by H-1B employer dependency status",
    x = "DOL Wage Level",
    y = "Share earning more than comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# --- Average Premium by Wage Level (Overall) ---
wage_level_avg_overall <- wage_level_data %>%
  filter(!is.na(Native)) %>%
  mutate(personal_premium = INCWAGE - Native) %>%
  group_by(wage_level) %>%
  summarise(
    avg_premium = mean(personal_premium, na.rm = TRUE),
    n = n(),
    .groups = "drop"
  )

ggplot(wage_level_avg_overall, aes(x = wage_level, y = avg_premium, fill = wage_level)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = dollar(avg_premium / 1000, accuracy = 1, suffix = "k")),
            vjust = ifelse(wage_level_avg_overall$avg_premium >= 0, -0.4, 1.2), size = 3.5) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black, linewidth = 0.5) +
  scale_fill_manual(values = ifp_wage_level_colors) +
  scale_y_continuous(labels = dollar, expand = expansion(mult = c(0.05, 0.08))) +
  labs(
    title = "Average Wage Premium by DOL Wage Level",
    subtitle = "Compared to median native with same age, occupation, and education",
    x = "DOL Wage Level",
    y = "Average premium vs. comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b() +
  theme(legend.position = "none")

# --- Average Premium by Wage Level and H-1B Dependency ---
wage_level_avg_by_dep <- wage_level_data %>%
  filter(!is.na(Native)) %>%
  mutate(personal_premium = INCWAGE - Native) %>%
  group_by(wage_level, h1b_dependent) %>%
  summarise(
    avg_premium = mean(personal_premium, na.rm = TRUE),
    n = n(),
    .groups = "drop"
  )

ggplot(wage_level_avg_by_dep, aes(x = wage_level, y = avg_premium, fill = h1b_dependent)) +
  geom_col(position = position_dodge(0.9), width = 0.8) +
  geom_text(aes(label = dollar(avg_premium / 1000, accuracy = 1, suffix = "k")),
            position = position_dodge(0.9), vjust = -0.4, size = 3) +
  geom_hline(yintercept = 0, linetype = "dashed", color = ifp_colors$rich_black, linewidth = 0.5) +
  scale_fill_manual(values = c("Y" = ifp_colors$dark_blue, "N" = ifp_colors$orange),
                    labels = c("Y" = "Yes", "N" = "No"),
                    name = "H-1B dependent?") +
  scale_y_continuous(labels = dollar, expand = expansion(mult = c(0.05, 0.08))) +
  labs(
    title = "Average Wage Premium by DOL Wage Level and H-1B Dependency Status",
    subtitle = "Compared to median native with same age, occupation, and education",
    x = "DOL Wage Level",
    y = "Average premium vs. comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# =============================================================================
# 13. Salary vs. Premium Relationship
# =============================================================================

scatter_data <- h1b_merged$full %>%
  filter(H1B == 1, !is.na(Native), !is.na(wage_level),
         INCWAGE < 250000, AGE < 65) %>%
  mutate(
    personal_premium = INCWAGE - Native,
    wage_level = factor(wage_level, levels = c("I", "II", "III", "IV"))
  ) %>%
  filter(abs(personal_premium) < 250000)

ggplot(scatter_data, aes(x = INCWAGE, y = personal_premium)) +
  geom_point(alpha = 0.4, size = 0.8) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  scale_x_continuous(labels = dollar_format(scale = 0.001, suffix = "k")) +
  scale_y_continuous(labels = dollar_format(scale = 0.001, suffix = "k")) +
  labs(
    title = "H-1B Salary vs. Wage Premium Over Comparable Native-Born Workers",
    subtitle = str_wrap("Each point is one H-1B worker; dashed line = zero premium. The wage premium is the H-1B holders' salary vs. the median native-born worker with the same occupation, education, and age group.", width = 100),
    x = "H-1B Salary",
    y = "Premium vs. Median Native",
    caption = "Note: Filtered to salaries <$250k."
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

# =============================================================================
# 14. Summary Statistics
# =============================================================================

# Overall share with positive premium (full controls)
overall <- h1b_merged$full %>%
  filter(H1B == 1, !is.na(Native)) %>%
  summarise(
    n = n(),
    share_positive = mean(INCWAGE > Native),
    avg_premium = mean(INCWAGE - Native),
    median_premium = median(INCWAGE - Native)
  )

cat("Overall H-1B Premium Statistics (Full Controls):\n")
cat("  Sample size:", comma(overall$n), "\n")
cat("  Share with positive premium:", percent(overall$share_positive, accuracy = 0.1), "\n")
cat("  Average premium:", dollar(overall$avg_premium), "\n")
cat("  Median premium:", dollar(overall$median_premium), "\n")

# =============================================================================
# 15. LCA vs. Petition Wage Analysis
# =============================================================================

# Compare LCA wages to petition wages
lca_comparison <- h1b_raw %>%
  filter(!is.na(lca_wages_lower_bound), lca_wages_lower_bound > 0,
         !is.na(petition_annual_pay_clean), petition_annual_pay_clean > 0) %>%
  mutate(
    lca_petition_gap = petition_annual_pay_clean - lca_wages_lower_bound,
    gap_category = case_when(
      lca_petition_gap == 0 ~ "No gap (paid at LCA floor)",
      lca_petition_gap > 0 ~ "Petition > LCA (paid above floor)",
      lca_petition_gap < 0 ~ "Petition < LCA (below floor)"
    )
  )

lca_summary <- lca_comparison %>%
  group_by(gap_category) %>%
  summarise(
    Count = n(),
    `Median Petition Wage` = dollar(median(petition_annual_pay_clean)),
    `Median LCA Wage` = dollar(median(lca_wages_lower_bound)),
    `Median Gap` = dollar(median(lca_petition_gap)),
    .groups = "drop"
  ) %>%
  mutate(`Percent` = percent(Count / sum(Count), accuracy = 0.1))

knitr::kable(lca_summary, caption = "LCA vs. Petition Wage Comparison")

# =============================================================================
# 16. Wage Level and Age Correlation
# =============================================================================

wage_level_age <- panel %>%
  filter(H1B == 1, !is.na(wage_level), wage_level %in% c("I", "II", "III", "IV")) %>%
  group_by(wage_level) %>%
  summarise(
    `Mean Age` = round(mean(AGE, na.rm = TRUE), 1),
    `10th %ile` = round(quantile(AGE, 0.10, na.rm = TRUE), 0),
    `25th %ile` = round(quantile(AGE, 0.25, na.rm = TRUE), 0),
    `Median` = round(quantile(AGE, 0.50, na.rm = TRUE), 0),
    `75th %ile` = round(quantile(AGE, 0.75, na.rm = TRUE), 0),
    `90th %ile` = round(quantile(AGE, 0.90, na.rm = TRUE), 0),
    `N` = comma(n()),
    .groups = "drop"
  )

knitr::kable(wage_level_age, caption = "Age Distribution by DOL Wage Level")

panel %>%
  filter(H1B == 1, !is.na(wage_level), wage_level %in% c("I", "II", "III", "IV")) %>%
  ggplot(aes(x = wage_level, y = AGE, fill = wage_level)) +
  geom_boxplot(alpha = 0.7) +
  scale_fill_manual(values = ifp_wage_level_colors) +
  labs(
    title = "Age Distribution by DOL Wage Level",
    subtitle = "Higher wage levels tend to have older workers",
    x = "DOL Wage Level",
    y = "Age",
    caption = "Source: FY 2022-2024 H-1B data"
  ) +
  theme_h1b() +
  theme(legend.position = "none")

# =============================================================================
# 17. Major Outsourcers Analysis
# =============================================================================

# Major IT outsourcing firms
major_outsourcers <- c(
  "Infosys Limited", "Cognizant Technology Solutions US Corp", "Accenture LLP",
 "Tech Mahindra Americas Inc", "Tech Mahindra Americas Inc.",
 "Tata Consultancy Services Limited", "Wipro Limited", "WIPRO LIMITED",
 "Mindtree Limited", "MindTree Limited", "LTIMINDTREE LIMITED",
 "Capgemini America, Inc.", "Deloitte Consulting LLP", "HCL America Inc",
 "IBM Corporation", "IBM Corp", "Ernst & Young U.S. LLP",
 "Larsen & Toubro Infotech Limited", "ATOS SYNTEL INC"
)

# Tag outsourcers in the data
outsourcer_data <- h1b_raw %>%
  mutate(
    is_outsourcer = ifelse(registration_employer_name %in% major_outsourcers,
                           "Major Outsourcer", "Other Employer")
  ) %>%
  group_by(is_outsourcer) %>%
  summarise(
    Count = n(),
    `Median Salary` = dollar(median(petition_annual_pay_clean, na.rm = TRUE)),
    `Mean Salary` = dollar(mean(petition_annual_pay_clean, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  mutate(`Share of Total` = percent(Count / sum(Count), accuracy = 0.1))

knitr::kable(outsourcer_data, caption = "H-1B Petitions: Major Outsourcers vs. Other Employers")

# --- Outsourcer Wage Level Distribution ---
h1b_raw %>%
  filter(!is.na(wage_level_combined), wage_level_combined %in% c("I", "II", "III", "IV")) %>%
  mutate(
    is_outsourcer = ifelse(registration_employer_name %in% major_outsourcers,
                           "Major Outsourcer", "Other Employer")
  ) %>%
  group_by(is_outsourcer, wage_level_combined) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(is_outsourcer) %>%
  mutate(pct = n / sum(n)) %>%
  ggplot(aes(x = wage_level_combined, y = pct, fill = is_outsourcer)) +
  geom_col(position = position_dodge(0.9), width = 0.8) +
  geom_text(aes(label = percent(pct, accuracy = 1)),
            position = position_dodge(0.9), vjust = -0.4, size = 3) +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.1))) +
  scale_fill_manual(values = c("Major Outsourcer" = ifp_colors$red, "Other Employer" = ifp_colors$dark_blue)) +
  labs(
    title = "Distribution of DOL Wage Levels: Outsourcers vs. Other Employers",
    subtitle = "Major outsourcers use more Level I positions",
    x = "DOL Wage Level",
    y = "Share of Employer's H-1B Petitions",
    fill = NULL,
    caption = "Source: FY 2022-2024 H-1B data"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")


# =============================================================================
# 18. Example Occupations
# =============================================================================

# Load H-1B data (reuse already loaded)
h1b_cols <- c("SOC_CODE", "registration_birth_year", "petition_annual_pay_clean")

h1b <- h1b_raw %>%
  transmute(
    YEAR = registration_lottery_year,
    AGE = YEAR - registration_birth_year,
    OCCSOC = as.character(as.numeric(gsub("-", "", SOC_CODE))),
    INCWAGE = petition_annual_pay_clean,
    PERWT = 1,  # H-1B records are unweighted (each = 1 person)
    group = "H-1B"
  ) %>%
  filter(!is.na(AGE), INCWAGE > 0, !is.na(OCCSOC))

cat("H-1B records:", nrow(h1b), "\n")

# Natives data for section 18
natives <- acs_raw %>%
  filter(
    CITIZEN %in% c(0, 1),
    INCWAGE > 0 & !INCWAGE %in% c(999998, 999999),
    EMPSTAT == 1
  ) %>%
  transmute(
    YEAR,
    AGE,
    OCCSOC = as.character(OCCSOC),
    INCWAGE,
    PERWT,  # ACS person weight for representative estimates
    group = "Native-born"
  )

cat("Native-born records:", nrow(natives), "\n")

# Load SOC definitions for labels
soc_codes <- read_excel("soc_2018_definitions.xlsx", skip = 7) %>%
  mutate(soc_numeric = str_remove_all(`SOC Code`, "-"))

occ_labels <- soc_codes %>%
  filter(`SOC Group` == "Detailed") %>%
  select(OCCSOC = soc_numeric, occ_title = `SOC Title`)

# --- Top 30 SOC Codes ---
# Get SOC codes that exist in native-born data
native_soc_codes <- natives %>%
  distinct(OCCSOC) %>%
  pull(OCCSOC)

# Find top 30 H-1B occupations that have native comparisons
top_30_soc <- h1b %>%
  filter(OCCSOC %in% native_soc_codes) %>%  # Only occupations with native data
  dplyr::count(OCCSOC, sort = TRUE) %>%
  head(30) %>%
  left_join(occ_labels, by = "OCCSOC")

cat("Top 30 SOC codes by H-1B petition count (with native comparisons available):\n\n")
top_30_soc %>%
  mutate(rank = row_number()) %>%
  select(rank, OCCSOC, occ_title, n) %>%
  knitr::kable(col.names = c("Rank", "SOC Code", "Occupation", "H-1B Count"))

# --- Wage Distribution Comparison Function ---
# Function to create a faceted wage distribution comparison plot
# Two panels stacked vertically:
#   Top: H-1B (age group) vs Native (same age group)
#   Bottom: H-1B (age group) vs Native (ALL ages)
# Uses PERWT weights for ACS data to produce representative estimates
plot_wage_distribution <- function(data, occ_code, occ_name, age_min, age_max, age_label) {

  # Get H-1B workers in the specified age range
  h1b_age <- data %>%
    filter(OCCSOC == occ_code, group == "H-1B",
           AGE >= age_min, AGE <= age_max, INCWAGE > 0)

  # Get native workers in the same age range
  native_age <- data %>%
    filter(OCCSOC == occ_code, group == "Native-born",
           AGE >= age_min, AGE <= age_max, INCWAGE > 0)

  # Get ALL native workers in this occupation (any age)
  native_all <- data %>%
    filter(OCCSOC == occ_code, group == "Native-born", INCWAGE > 0)

  # Check minimum observations
  if (nrow(h1b_age) < 30 || nrow(native_age) < 30) {
    return(NULL)
  }

  # Create comparison datasets with facet labels
  # Panel 1: H-1B vs Native (same age)
  panel1 <- bind_rows(
    h1b_age %>% mutate(comparison = paste0("vs. Native Age ", age_label)),
    native_age %>% mutate(comparison = paste0("vs. Native Age ", age_label))
  )

  # Panel 2: H-1B vs Native (all ages)
  panel2 <- bind_rows(
    h1b_age %>% mutate(comparison = "vs. Native All Ages"),
    native_all %>% mutate(comparison = "vs. Native All Ages")
  )

  # Combine for faceted plot
  df <- bind_rows(panel1, panel2) %>%
    mutate(
      group = factor(group, levels = c("Native-born", "H-1B")),
      comparison = factor(comparison, levels = c(paste0("vs. Native Age ", age_label),
                                                  "vs. Native All Ages"))
    )

  # Calculate WEIGHTED medians for each panel
  med <- df %>%
    group_by(comparison, group) %>%
    summarise(med_wage = weightedMedian(INCWAGE, w = PERWT, na.rm = TRUE),
              n = n(),
              .groups = "drop") %>%
    group_by(comparison) %>%
    mutate(
      hjust = if_else(med_wage == min(med_wage), 1.05, -0.05),
      med_lab = paste0("Median: ", label_dollar()(med_wage))
    ) %>%
    ungroup()

  # Get sample sizes for subtitle
  n_h1b <- nrow(h1b_age)
  n_native_age <- nrow(native_age)
  n_native_all <- nrow(native_all)

  ggplot(df, aes(INCWAGE, fill = group)) +
    geom_density(aes(weight = PERWT), alpha = 0.35, adjust = 1) +
    geom_vline(data = med, aes(xintercept = med_wage, color = group),
               linewidth = 0.8, show.legend = FALSE) +
    geom_text(data = med, aes(x = med_wage, y = Inf, label = med_lab, color = group, hjust = hjust),
              vjust = 1.2, size = 3, show.legend = FALSE) +
    facet_wrap(~ comparison, ncol = 1, scales = "free_y") +
    scale_x_continuous(labels = label_dollar(), limits = c(0, 300000)) +
    scale_fill_manual(values = c("Native-born" = ifp_colors$purple, "H-1B" = ifp_colors$orange)) +
    scale_color_manual(values = c("Native-born" = ifp_colors$purple, "H-1B" = ifp_colors$orange)) +
    labs(
      title = str_wrap(occ_name, width = 60),
      subtitle = paste0("H-1B workers age ", age_label, " (n=", scales::comma(n_h1b),
                        ") | Native age ", age_label, " (n=", scales::comma(n_native_age),
                        ") | Native all ages (n=", scales::comma(n_native_all), ")"),
      x = "Wage and Salary Income",
      y = "Density",
      fill = NULL
    ) +
    theme_h1b() +
    theme(strip.text = element_text(size = 10, face = "bold"))
}

# Combine H-1B and native-born data
combined <- bind_rows(h1b, natives)

# --- Age 25-29: Early Career ---
for (i in 1:nrow(top_30_soc)) {
  occ_code <- top_30_soc$OCCSOC[i]
  occ_name <- top_30_soc$occ_title[i]

  p <- plot_wage_distribution(combined, occ_code, occ_name, 25, 29, "25-29")

  if (!is.null(p)) {
    cat("\n\n### ", i, ". ", occ_name, "\n\n", sep = "")
    print(p)
  }
}

# --- Age 40-44: Mid-Career ---
for (i in 1:nrow(top_30_soc)) {
  occ_code <- top_30_soc$OCCSOC[i]
  occ_name <- top_30_soc$occ_title[i]

  p <- plot_wage_distribution(combined, occ_code, occ_name, 40, 44, "40-44")

  if (!is.null(p)) {
    cat("\n\n### ", i, ". ", occ_name, "\n\n", sep = "")
    print(p)
  }
}

# --- Summary Statistics ---
# Calculate summary stats for all top 30 occupations using PERWT weights
summary_stats <- combined %>%
  filter(OCCSOC %in% top_30_soc$OCCSOC) %>%
  mutate(age_group = case_when(
    AGE >= 25 & AGE <= 29 ~ "25-29",
    AGE >= 40 & AGE <= 44 ~ "40-44",
    TRUE ~ NA_character_
  )) %>%
  filter(!is.na(age_group)) %>%
  left_join(occ_labels, by = "OCCSOC") %>%
  group_by(occ_title, age_group, group) %>%
  summarise(
    n = n(),
    median_wage = weightedMedian(INCWAGE, w = PERWT, na.rm = TRUE),
    mean_wage = weighted.mean(INCWAGE, w = PERWT, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(occ_title, age_group, group)

# Calculate H-1B premium (median difference)
premium_summary <- summary_stats %>%
  select(occ_title, age_group, group, median_wage) %>%
  pivot_wider(names_from = group, values_from = median_wage) %>%
  mutate(
    h1b_premium = `H-1B` - `Native-born`,
    h1b_premium_pct = h1b_premium / `Native-born` * 100
  ) %>%
  arrange(age_group, desc(h1b_premium))

cat("\n\n## H-1B Wage Premium by Occupation and Age Group\n\n")
cat("Positive values indicate H-1B median exceeds native-born median.\n\n")

premium_summary %>%
  mutate(
    `Native-born` = dollar(`Native-born`),
    `H-1B` = dollar(`H-1B`),
    h1b_premium = dollar(h1b_premium),
    h1b_premium_pct = paste0(round(h1b_premium_pct, 1), "%")
  ) %>%
  knitr::kable(
    col.names = c("Occupation", "Age Group", "Native Median", "H-1B Median", "Premium ($)", "Premium (%)"),
    align = c("l", "c", "r", "r", "r", "r")
  )

# --- Combined View: Information Security Analysts ---
# Information Security Analysts SOC code
info_sec_code <- "151212"
info_sec_name <- "Information Security Analysts"

# Build all four panels
build_panel <- function(data, occ_code, age_min, age_max, age_label, comparison_type) {

  # Get H-1B workers in the specified age range
  h1b_age <- data %>%
    filter(OCCSOC == occ_code, group == "H-1B",
           AGE >= age_min, AGE <= age_max, INCWAGE > 0)

  if (comparison_type == "same_age") {
    # Get native workers in the same age range
    native_compare <- data %>%
      filter(OCCSOC == occ_code, group == "Native-born",
             AGE >= age_min, AGE <= age_max, INCWAGE > 0)
    panel_label <- paste0("vs. Native Age ", age_label)
  } else {
    # Get ALL native workers in this occupation
    native_compare <- data %>%
      filter(OCCSOC == occ_code, group == "Native-born", INCWAGE > 0)
    panel_label <- "vs. Native All Ages"
  }

  bind_rows(
    h1b_age %>% mutate(comparison = panel_label, age_group = age_label),
    native_compare %>% mutate(comparison = panel_label, age_group = age_label)
  )
}

# Create all four combinations
panel_data <- bind_rows(
  build_panel(combined, info_sec_code, 25, 29, "25-29", "same_age"),
  build_panel(combined, info_sec_code, 25, 29, "25-29", "all_ages"),
  build_panel(combined, info_sec_code, 40, 44, "40-44", "same_age"),
  build_panel(combined, info_sec_code, 40, 44, "40-44", "all_ages")
) %>%
  mutate(
    group = factor(group, levels = c("Native-born", "H-1B")),
    age_group = factor(age_group, levels = c("25-29", "40-44")),
    comparison = factor(comparison, levels = c("vs. Native Age 25-29", "vs. Native Age 40-44", "vs. Native All Ages"))
  )

# Fix comparison factor to have consistent ordering for facet_grid
panel_data <- panel_data %>%
  mutate(
    comparison_row = case_when(
      comparison %in% c("vs. Native Age 25-29", "vs. Native Age 40-44") ~ "vs. Native Same Age",
      TRUE ~ "vs. Native All Ages"
    ),
    comparison_row = factor(comparison_row, levels = c("vs. Native Same Age", "vs. Native All Ages"))
  )

# Calculate medians for each panel
med_combined <- panel_data %>%
  group_by(age_group, comparison_row, group) %>%
  summarise(med_wage = weightedMedian(INCWAGE, w = PERWT, na.rm = TRUE),
            n = n(),
            .groups = "drop") %>%
  group_by(age_group, comparison_row) %>%
  mutate(
    hjust = if_else(med_wage == min(med_wage), 1.05, -0.05),
    med_lab = paste0("Median: ", label_dollar()(med_wage))
  ) %>%
  ungroup()

# Create the 2x2 grid plot
ggplot(panel_data, aes(INCWAGE, fill = group)) +
  geom_density(aes(weight = PERWT), alpha = 0.35, adjust = 1) +
  geom_vline(data = med_combined, aes(xintercept = med_wage, color = group),
             linewidth = 0.8, show.legend = FALSE) +
  geom_text(data = med_combined, aes(x = med_wage, y = Inf, label = med_lab,
                                      color = group, hjust = hjust),
            vjust = 1.2, size = 3, show.legend = FALSE) +
  facet_grid(comparison_row ~ age_group, scales = "free_y") +
  scale_x_continuous(labels = label_dollar(), limits = c(0, 300000)) +
  scale_fill_manual(values = c("Native-born" = ifp_colors$purple, "H-1B" = ifp_colors$orange)) +
  scale_color_manual(values = c("Native-born" = ifp_colors$purple, "H-1B" = ifp_colors$orange)) +
  labs(
    title = info_sec_name,
    subtitle = "H-1B wage distributions compared to native-born workers by age group",
    x = "Wage and Salary Income",
    y = "Density",
    fill = NULL
  ) +
  theme_h1b() +
  theme(
    strip.text = element_text(size = 11, face = "bold"),
    legend.position = "bottom"
  )

# =============================================================================
# 19. High-Wage H-1Bs: Workers Exceeding Level III
# =============================================================================

# Load raw data with Level3 thresholds
h1b_with_levels <- h1b_raw %>%
  filter(
    !is.na(Level3_full) | !is.na(Level3_part),
    !is.na(petition_annual_pay_clean),
    petition_annual_pay_clean > 0
  ) %>%
  mutate(
    # Determine which Level3 threshold to use based on full-time status
    level3_threshold = case_when(
      petition_beneficiary_full_time == "N" ~ Level3_part,
      TRUE ~ Level3_full  # "Y" or blank/missing = full-time
    ),
    # Flag workers exceeding Level III
    exceeds_level3 = petition_annual_pay_clean >= level3_threshold
  )

# Summary of Level III exceedance
level3_summary <- h1b_with_levels %>%
  summarise(
    total = n(),
    exceeds_l3 = sum(exceeds_level3, na.rm = TRUE),
    pct_exceeds = mean(exceeds_level3, na.rm = TRUE)
  )

cat("H-1B Workers Relative to Level III Threshold:\n")
cat("  Total with valid Level III data:", comma(level3_summary$total), "\n")
cat("  Exceeding Level III:", comma(level3_summary$exceeds_l3),
    "(", percent(level3_summary$pct_exceeds, accuracy = 0.1), ")\n")

# --- Prepare High-Wage H-1B Panel ---
# Filter to workers exceeding Level III and prepare for premium analysis
h1b_level3_plus <- h1b_with_levels %>%
  filter(exceeds_level3 == TRUE) %>%
  transmute(
    YEAR = registration_lottery_year,
    AGE = YEAR - registration_birth_year,
    OCCSOC = as.character(as.numeric(gsub("-", "", SOC_CODE))),
    EDUCD = map_education_code(petition_beneficiary_edu_code),
    INCWAGE = petition_annual_pay_clean,
    h1b_dependent = petition_employer_h1b_dependent,
    employer_name = registration_employer_name,
    is_outsourcer = ifelse(registration_employer_name %in% major_outsourcers,
                           "Major Outsourcer", "Other Employer"),
    H1B = 1L,
    PERWT = 1
  ) %>%
  filter(!is.na(AGE), AGE >= 20, AGE < 65, INCWAGE > 0) %>%
  mutate(
    EDUCD = as.factor(EDUCD),
    OCCSOC = as.factor(OCCSOC),
    age_grp = cut(AGE,
                  breaks = c(20, 25, 30, 35, 40, 45, 50, 55, 60, 65),
                  right = FALSE, include.lowest = TRUE)
  )

cat("\nHigh-wage H-1B workers (exceeding Level III):", nrow(h1b_level3_plus), "\n")
cat("  At major outsourcers:", sum(h1b_level3_plus$is_outsourcer == "Major Outsourcer"), "\n")
cat("  At other employers:", sum(h1b_level3_plus$is_outsourcer == "Other Employer"), "\n")

# Merge with native benchmarks (full controls: age + education + occupation)
h1b_level3_merged <- h1b_level3_plus %>%
  left_join(native_median$full, by = c("YEAR", "EDUCD", "OCCSOC", "age_grp"))

# Check merge rate
merge_rate <- mean(!is.na(h1b_level3_merged$Native))
cat("  Matched to native benchmark:", percent(merge_rate, accuracy = 0.1), "\n")

# --- Share with Negative Premium (Full Controls) ---
# Calculate share with negative premium
level3_premium_stats <- h1b_level3_merged %>%
  filter(!is.na(Native)) %>%
  mutate(
    personal_premium = INCWAGE - Native,
    has_negative_premium = personal_premium < 0
  ) %>%
  summarise(
    n = n(),
    n_negative = sum(has_negative_premium),
    share_negative = mean(has_negative_premium),
    avg_premium = mean(personal_premium),
    median_premium = median(personal_premium)
  )

cat("\nWage Premium Statistics for H-1Bs Exceeding Level III:\n")
cat("  Sample size (with native benchmark):", comma(level3_premium_stats$n), "\n")
cat("  Share with NEGATIVE premium:", percent(level3_premium_stats$share_negative, accuracy = 0.1), "\n")
cat("  Average premium:", dollar(level3_premium_stats$avg_premium), "\n")
cat("  Median premium:", dollar(level3_premium_stats$median_premium), "\n")

# --- Share with Negative Premium by Employer Type ---
# Calculate share with negative premium by employer type
level3_by_employer <- h1b_level3_merged %>%
  filter(!is.na(Native)) %>%
  mutate(
    personal_premium = INCWAGE - Native,
    has_negative_premium = personal_premium < 0
  ) %>%
  group_by(is_outsourcer) %>%
  summarise(
    n = n(),
    n_negative = sum(has_negative_premium),
    share_negative = mean(has_negative_premium),
    avg_premium = mean(personal_premium),
    median_premium = median(personal_premium),
    .groups = "drop"
  )

cat("\nShare with Negative Premium by Employer Type (Level III+ workers):\n\n")
level3_by_employer %>%
  mutate(
    `Share Negative` = percent(share_negative, accuracy = 0.1),
    `Avg Premium` = dollar(avg_premium),
    `Median Premium` = dollar(median_premium),
    n = comma(n)
  ) %>%
  select(is_outsourcer, n, `Share Negative`, `Avg Premium`, `Median Premium`) %>%
  knitr::kable(col.names = c("Employer Type", "N", "Share with Negative Premium",
                              "Average Premium", "Median Premium"))

ggplot(level3_by_employer, aes(x = is_outsourcer, y = share_negative, fill = is_outsourcer)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = percent(share_negative, accuracy = 0.1)), vjust = -0.4, size = 4) +
  scale_y_continuous(labels = percent, limits = c(0, max(level3_by_employer$share_negative) * 1.15),
                     expand = expansion(mult = c(0, 0))) +
  scale_fill_manual(values = c("Major Outsourcer" = ifp_colors$red,
                               "Other Employer" = ifp_colors$dark_blue)) +
  labs(
    title = "Share of High-Wage H-1Bs with Negative Wage Premium",
    subtitle = "Among workers paid above OFLC Level III, compared to median native with same age, education, and occupation",
    x = NULL,
    y = "Share earning less than comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b() +
  theme(legend.position = "none")

# --- Share with Negative Premium by Age Group and Employer Type ---
# Calculate by age group and employer type
level3_by_age_employer <- h1b_level3_merged %>%
  filter(!is.na(Native), !is.na(age_grp)) %>%
  mutate(
    personal_premium = INCWAGE - Native,
    has_negative_premium = personal_premium < 0
  ) %>%
  group_by(age_grp, is_outsourcer) %>%
  summarise(
    n = n(),
    share_negative = mean(has_negative_premium),
    .groups = "drop"
  ) %>%
  filter(n >= 20)  # Only show groups with sufficient sample size

ggplot(level3_by_age_employer, aes(x = age_grp, y = share_negative, fill = is_outsourcer)) +
  geom_col(position = position_dodge(0.9), width = 0.8) +
  geom_text(aes(label = percent(share_negative, accuracy = 1)),
            position = position_dodge(0.9), vjust = -0.4, size = 2.8) +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.1))) +
  scale_x_discrete(labels = age_labels) +
  scale_fill_manual(values = c("Major Outsourcer" = ifp_colors$red,
                               "Other Employer" = ifp_colors$dark_blue)) +
  labs(
    title = "Share with Negative Premium by Age: H-1Bs Exceeding Occupational Median Wage",
    subtitle = "Compared to median native with same age, education, and occupation",
    x = "Age of H-1B recipient",
    y = "Share earning less than comparable natives",
    fill = NULL,
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS\nNote: Only age groups with n >= 20 shown"
  ) +
  theme_h1b() +
  theme(legend.position = "bottom")

# --- Comparison Across Wage Levels (II, III) ---
# Function to analyze workers exceeding a given wage level
analyze_level <- function(data, level_col_full, level_col_part, level_name) {

  # Prepare data with appropriate threshold
  level_data <- data %>%
    filter(
      !is.na(.data[[level_col_full]]) | !is.na(.data[[level_col_part]]),
      !is.na(petition_annual_pay_clean),
      petition_annual_pay_clean > 0
    ) %>%
    mutate(
      threshold = case_when(
        petition_beneficiary_full_time == "N" ~ .data[[level_col_part]],
        TRUE ~ .data[[level_col_full]]
      ),
      exceeds_level = petition_annual_pay_clean >= threshold
    )

  # Filter to those exceeding the threshold and prepare for merge
  exceeds_data <- level_data %>%
    filter(exceeds_level == TRUE) %>%
    transmute(
      YEAR = registration_lottery_year,
      AGE = registration_lottery_year - registration_birth_year,
      OCCSOC = as.character(as.numeric(gsub("-", "", SOC_CODE))),
      EDUCD = map_education_code(petition_beneficiary_edu_code),
      INCWAGE = petition_annual_pay_clean,
      is_outsourcer = ifelse(registration_employer_name %in% major_outsourcers,
                             "Major Outsourcer", "Other Employer"),
      H1B = 1L,
      PERWT = 1
    ) %>%
    filter(!is.na(AGE), AGE >= 20, AGE < 65, INCWAGE > 0) %>%
    mutate(
      EDUCD = as.factor(EDUCD),
      OCCSOC = as.factor(OCCSOC),
      age_grp = cut(AGE,
                    breaks = c(20, 25, 30, 35, 40, 45, 50, 55, 60, 65),
                    right = FALSE, include.lowest = TRUE)
    )

  # Merge with native benchmarks
  merged_data <- exceeds_data %>%
    left_join(native_median$full, by = c("YEAR", "EDUCD", "OCCSOC", "age_grp"))

  # Calculate overall stats
  overall_stats <- merged_data %>%
    filter(!is.na(Native)) %>%
    mutate(
      personal_premium = INCWAGE - Native,
      has_negative_premium = personal_premium < 0
    ) %>%
    summarise(
      level = level_name,
      n_exceeding = nrow(exceeds_data),
      n_with_benchmark = n(),
      share_negative = mean(has_negative_premium),
      avg_premium = mean(personal_premium),
      median_premium = median(personal_premium)
    )

  # Calculate by employer type
  by_employer <- merged_data %>%
    filter(!is.na(Native)) %>%
    mutate(
      personal_premium = INCWAGE - Native,
      has_negative_premium = personal_premium < 0
    ) %>%
    group_by(is_outsourcer) %>%
    summarise(
      n = n(),
      share_negative = mean(has_negative_premium),
      .groups = "drop"
    ) %>%
    mutate(level = level_name)

  list(overall = overall_stats, by_employer = by_employer)
}

# Analyze all three levels
level2_results <- analyze_level(h1b_raw, "Level2_full", "Level2_part", "Level II")
level3_results <- analyze_level(h1b_raw, "Level3_full", "Level3_part", "Level III")

# Combine overall results
overall_comparison <- bind_rows(
  level2_results$overall,
  level3_results$overall
)

cat("Share with Negative Premium by Wage Level Threshold:\n\n")
overall_comparison %>%
  mutate(
    `N Exceeding Threshold` = comma(n_exceeding),
    `N with Benchmark` = comma(n_with_benchmark),
    `Share Negative` = percent(share_negative, accuracy = 0.1),
    `Avg Premium` = dollar(avg_premium),
    `Median Premium` = dollar(median_premium)
  ) %>%
  select(level, `N Exceeding Threshold`, `N with Benchmark`, `Share Negative`,
         `Avg Premium`, `Median Premium`) %>%
  knitr::kable(col.names = c("Wage Level Threshold", "N Exceeding", "N with Benchmark",
                              "Share with Negative Premium", "Avg Premium", "Median Premium"))

# Combine by-employer results
employer_comparison <- bind_rows(
  level2_results$by_employer,
  level3_results$by_employer
) %>%
  mutate(level = factor(level, levels = c("Level II", "Level III")))

cat("\nShare with Negative Premium by Wage Level and Employer Type:\n\n")
employer_comparison %>%
  mutate(
    n = comma(n),
    `Share Negative` = percent(share_negative, accuracy = 0.1)
  ) %>%
  pivot_wider(
    id_cols = is_outsourcer,
    names_from = level,
    values_from = c(n, `Share Negative`)
  ) %>%
  knitr::kable()

# --- Wage Level Comparison Chart ---
# Custom labels for each level (edit these as needed)
level_labels <- c(
 "Level II" = "Set Minimum to 34th Percentile",
 "Level III" = "Set Minimum to 50th Percentile ",
 "IFP Proposal" = "Experience Benchmarking"
)

# Create overall summary (not broken out by employer)
overall_for_chart <- overall_comparison %>%
 select(level, share_negative) %>%
 # Add IFP Proposal row with 0%
 bind_rows(tibble(level = "IFP Proposal", share_negative = 0)) %>%
 mutate(level = factor(level, levels = c("Level II", "Level III", "IFP Proposal")))

ggplot(overall_for_chart, aes(x = level, y = share_negative, fill = level)) +
 geom_col(width = 0.7) +
 geom_text(aes(label = percent(share_negative, accuracy = 0.1)),
           vjust = -0.4, size = 3.5) +
 scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.12))) +
 scale_x_discrete(labels = level_labels) +
 scale_fill_manual(values = c("Level II" = ifp_colors$light_blue,
                              "Level III" = ifp_colors$purple,
                              "IFP Proposal" = ifp_colors$green)) +
 labs(
   title = "Raising wage levels without data on experience and education can't end underpayment",
   subtitle = "Initial cap-subject H-1Bs compared to natives with same occupation, age, and education",
   x = "Salary threshold proposals",
   y = "Share earning less than comparable natives",
   caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
 ) +
 theme_h1b() +
  theme(legend.position = "none",
       panel.grid.major.x = element_blank())

# =============================================================================
# 20. Employer Analysis: Who Pays Above/Below Native Benchmarks?
# =============================================================================
#
# This section analyzes which employers have the highest and lowest rates of
# H-1B workers earning more than comparable native-born workers.
#
# We focus on "large" employers: those with 500+ H-1B petitions in FY2022-2024.

# --- Step 1: Prepare H-1B data with employer names ---
# Start fresh from h1b_raw to include employer_name
h1b_with_employers <- h1b_raw %>%
  transmute(
    # Use lottery year as the reference year
    YEAR = registration_lottery_year,
    # Calculate age from birth year
    AGE = registration_lottery_year - registration_birth_year,
    # Clean SOC code: remove dashes and convert to character
    OCCSOC = as.character(as.numeric(gsub("-", "", SOC_CODE))),
    # Map education codes (A-I) to IPUMS EDUCD values
    EDUCD = map_education_code(petition_beneficiary_edu_code),
    # Annual salary
    INCWAGE = petition_annual_pay_clean,
    # Employer name for grouping
    employer_name = registration_employer_name,
    # Flag as H-1B worker
    H1B = 1L
  ) %>%
  # Remove invalid records
  filter(
    !is.na(AGE),
    AGE >= 20,
    AGE < 65,
    INCWAGE > 0,
    !is.na(OCCSOC),
    EDUCD != 0  # Need valid education for full controls
  ) %>%
  # Create factors and age groups to match the native benchmark format

  mutate(
    EDUCD = as.factor(EDUCD),
    OCCSOC = as.factor(OCCSOC),
    age_grp = cut(AGE,
                  breaks = c(20, 25, 30, 35, 40, 45, 50, 55, 60, 65),
                  right = FALSE, include.lowest = TRUE)
  )

cat("H-1B records with employer names:", nrow(h1b_with_employers), "\n")

# --- Step 2: Merge with native wage benchmarks ---
# We use the "full controls" benchmark: same year, education, occupation, and age
h1b_employer_merged <- h1b_with_employers %>%
  left_join(native_median$full, by = c("YEAR", "EDUCD", "OCCSOC", "age_grp"))

# Check how many matched
matched_count <- sum(!is.na(h1b_employer_merged$Native))
cat("Records matched to native benchmark:", comma(matched_count),
    "(", percent(matched_count / nrow(h1b_employer_merged), accuracy = 0.1), ")\n")

# --- Step 3: Calculate premium for each worker ---
h1b_employer_premium <- h1b_employer_merged %>%
  filter(!is.na(Native)) %>%  # Keep only those with a valid benchmark

  mutate(
    # Premium = H-1B wage minus native median wage
    personal_premium = INCWAGE - Native,
    # Flag: does this worker earn MORE than comparable natives?
    has_positive_premium = personal_premium > 0
  )

# --- Step 4: Summarize by employer ---
# For each employer, calculate:
#   - Total number of H-1B workers (with valid benchmark)
#   - Number and share with positive premium (earning MORE than natives)
#   - Number and share with negative premium (earning LESS than natives)
#   - Average and median premium
employer_summary <- h1b_employer_premium %>%
  group_by(employer_name) %>%
  summarise(
    n_total = n(),
    n_positive = sum(has_positive_premium),
    n_negative = sum(!has_positive_premium),
    share_positive = mean(has_positive_premium),
    share_negative = mean(!has_positive_premium),
    avg_premium = mean(personal_premium),
    median_premium = median(personal_premium),
    avg_salary = mean(INCWAGE),
    .groups = "drop"
  ) %>%
  # Sort by total count (largest employers first)
  arrange(desc(n_total))

cat("\nTotal unique employers:", comma(nrow(employer_summary)), "\n")

# --- Step 5: Filter to large employers (500+ H-1Bs) ---
large_employers <- employer_summary %>%
  filter(n_total >= 500)

cat("Large employers (500+ H-1Bs):", nrow(large_employers), "\n")

# --- Step 6: Display results ---

# Top 20 largest employers overall
cat("\n--- TOP 20 LARGEST H-1B EMPLOYERS ---\n")
cat("(Ranked by total H-1B petitions with valid native benchmark)\n\n")

large_employers %>%
  head(20) %>%
  mutate(
    Rank = row_number(),
    `Total H-1Bs` = comma(n_total),
    `Share Positive` = percent(share_positive, accuracy = 0.1),
    `Share Negative` = percent(share_negative, accuracy = 0.1),
    `Avg Premium` = dollar(avg_premium),
    `Avg Salary` = dollar(avg_salary)
  ) %>%
  select(Rank, employer_name, `Total H-1Bs`, `Share Positive`, `Share Negative`,
         `Avg Premium`, `Avg Salary`) %>%
  knitr::kable(col.names = c("Rank", "Employer", "Total H-1Bs", "Share Paid Above Natives",
                              "Share Paid Below Natives", "Avg Premium", "Avg Salary"))

# Large employers with HIGHEST positive premium rates (best for H-1Bs)
cat("\n--- LARGE EMPLOYERS WITH HIGHEST SHARE PAID ABOVE NATIVES ---\n")
cat("(Among employers with 500+ H-1B petitions)\n\n")

top_positive_employers <- large_employers %>%
  arrange(desc(share_positive)) %>%
  head(20)

top_positive_employers %>%
  mutate(
    Rank = row_number(),
    `Total H-1Bs` = comma(n_total),
    `Share Positive` = percent(share_positive, accuracy = 0.1),
    `Share Negative` = percent(share_negative, accuracy = 0.1),
    `Avg Premium` = dollar(avg_premium),
    `Avg Salary` = dollar(avg_salary)
  ) %>%
  select(Rank, employer_name, `Total H-1Bs`, `Share Positive`, `Share Negative`,
         `Avg Premium`, `Avg Salary`) %>%
  knitr::kable(col.names = c("Rank", "Employer", "Total H-1Bs", "Share Paid Above Natives",
                              "Share Paid Below Natives", "Avg Premium", "Avg Salary"))

# Large employers with LOWEST positive premium rates (most underpayment)
cat("\n--- LARGE EMPLOYERS WITH HIGHEST SHARE PAID BELOW NATIVES ---\n")
cat("(Among employers with 500+ H-1B petitions)\n\n")

top_negative_employers <- large_employers %>%
  arrange(share_positive) %>%  # Lowest positive = highest negative
  head(20)

top_negative_employers %>%
  mutate(
    Rank = row_number(),
    `Total H-1Bs` = comma(n_total),
    `Share Positive` = percent(share_positive, accuracy = 0.1),
    `Share Negative` = percent(share_negative, accuracy = 0.1),
    `Avg Premium` = dollar(avg_premium),
    `Avg Salary` = dollar(avg_salary)
  ) %>%
  select(Rank, employer_name, `Total H-1Bs`, `Share Positive`, `Share Negative`,
         `Avg Premium`, `Avg Salary`) %>%
  knitr::kable(col.names = c("Rank", "Employer", "Total H-1Bs", "Share Paid Above Natives",
                              "Share Paid Below Natives", "Avg Premium", "Avg Salary"))

# --- Step 7: Visualizations ---

# Chart: Top 15 large employers with HIGHEST positive premium rates
ggplot(top_positive_employers %>% head(15),
       aes(x = reorder(str_wrap(employer_name, 30), share_positive),
           y = share_positive)) +
  geom_col(fill = ifp_colors$dark_blue, width = 0.7) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)),
            hjust = -0.1, size = 3) +
  coord_flip() +
  scale_y_continuous(labels = percent, limits = c(0, 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Large Employers with Highest Share of H-1Bs Paid Above Natives",
    subtitle = "Among employers with 500+ initial H-1B petitions, FY2022-2024",
    x = NULL,
    y = "Share earning more than comparable natives",
    caption = "Note: 'Comparable natives' = same occupation, education, and age group.\nSource: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# Chart: Top 15 large employers with LOWEST positive premium rates (most underpayment)
ggplot(top_negative_employers %>% head(15),
       aes(x = reorder(str_wrap(employer_name, 30), -share_negative),
           y = share_negative)) +
  geom_col(fill = ifp_colors$red, width = 0.7) +
  geom_text(aes(label = percent(share_negative, accuracy = 1)),
            hjust = -0.1, size = 3) +
  coord_flip() +
  scale_y_continuous(labels = percent, limits = c(0, 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Large Employers with Highest Share of H-1Bs Paid Below Natives",
    subtitle = "Among employers with 500+ initial H-1B petitions, FY2022-2024",
    x = NULL,
    y = "Share earning less than comparable natives",
    caption = "Note: 'Comparable natives' = same occupation, education, and age group.\nSource: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# --- Step 8: Summary statistics ---
cat("\n--- SUMMARY: LARGE EMPLOYERS (500+ H-1Bs) ---\n\n")

large_employer_stats <- large_employers %>%
  summarise(
    n_employers = n(),
    total_h1bs = sum(n_total),
    avg_share_positive = weighted.mean(share_positive, w = n_total),
    median_share_positive = median(share_positive),
    min_share_positive = min(share_positive),
    max_share_positive = max(share_positive)
  )

cat("Number of large employers:", large_employer_stats$n_employers, "\n")
cat("Total H-1Bs at large employers:", comma(large_employer_stats$total_h1bs), "\n")
cat("Weighted avg share with positive premium:",
    percent(large_employer_stats$avg_share_positive, accuracy = 0.1), "\n")
cat("Range of positive premium shares:",
    percent(large_employer_stats$min_share_positive, accuracy = 0.1), "to",
    percent(large_employer_stats$max_share_positive, accuracy = 0.1), "\n")

# =============================================================================
# 21. Industry Analysis: Premium Rates by NAICS Sector
# =============================================================================
#
# This section analyzes wage premiums by industry using NAICS codes.
# NAICS = North American Industry Classification System
# The first 2 digits indicate the sector (e.g., 54 = Professional Services)

# --- Step 1: Define NAICS sector labels ---
# These are the 2-digit NAICS sector codes and their descriptions
naics_sector_labels <- c(
  "11" = "Agriculture, Forestry, Fishing and Hunting",
  "21" = "Mining, Quarrying, and Oil and Gas Extraction",
  "22" = "Utilities",
  "23" = "Construction",
  "31" = "Manufacturing",
  "32" = "Manufacturing",
  "33" = "Manufacturing",
  "42" = "Wholesale Trade",
  "44" = "Retail Trade",
  "45" = "Retail Trade",
  "48" = "Transportation and Warehousing",
  "49" = "Transportation and Warehousing",
  "51" = "Information",
  "52" = "Finance and Insurance",
  "53" = "Real Estate and Rental and Leasing",
  "54" = "Professional, Scientific, and Technical Services",
  "55" = "Management of Companies and Enterprises",
  "56" = "Administrative and Support Services",
  "61" = "Educational Services",
  "62" = "Health Care and Social Assistance",
  "71" = "Arts, Entertainment, and Recreation",
  "72" = "Accommodation and Food Services",
  "81" = "Other Services (except Public Administration)",
  "92" = "Public Administration"
)

# --- Step 2: Prepare H-1B data with NAICS codes ---
# Start fresh from h1b_raw to include NAICS
h1b_with_naics <- h1b_raw %>%
  transmute(
    # Use lottery year as the reference year
    YEAR = registration_lottery_year,
    # Calculate age from birth year
    AGE = registration_lottery_year - registration_birth_year,
    # Clean SOC code: remove dashes and convert to character
    OCCSOC = as.character(as.numeric(gsub("-", "", SOC_CODE))),
    # Map education codes (A-I) to IPUMS EDUCD values
    EDUCD = map_education_code(petition_beneficiary_edu_code),
    # Annual salary
    INCWAGE = petition_annual_pay_clean,
    # NAICS code (full code, usually 6 digits)
    naics_full = as.character(petition_employer_naics),
    # Extract 2-digit sector code
    naics_sector = substr(as.character(petition_employer_naics), 1, 2),
    # Flag as H-1B worker
    H1B = 1L
  ) %>%
  # Remove invalid records
  filter(
    !is.na(AGE),
    AGE >= 20,
    AGE < 65,
    INCWAGE > 0,
    !is.na(OCCSOC),
    EDUCD != 0,  # Need valid education for full controls
    !is.na(naics_sector),
    naics_sector != ""
  ) %>%
  # Add sector name from lookup table
  mutate(
    EDUCD = as.factor(EDUCD),
    OCCSOC = as.factor(OCCSOC),
    age_grp = cut(AGE,
                  breaks = c(20, 25, 30, 35, 40, 45, 50, 55, 60, 65),
                  right = FALSE, include.lowest = TRUE),
    # Look up sector name; use "Unknown" if not found
    sector_name = ifelse(naics_sector %in% names(naics_sector_labels),
                         naics_sector_labels[naics_sector],
                         paste0("Unknown (", naics_sector, ")"))
  )

cat("\n\nH-1B records with NAICS codes:", nrow(h1b_with_naics), "\n")

# --- Step 3: Merge with native wage benchmarks ---
# We use the "full controls" benchmark: same year, education, occupation, and age
h1b_naics_merged <- h1b_with_naics %>%
  left_join(native_median$full, by = c("YEAR", "EDUCD", "OCCSOC", "age_grp"))

# Check how many matched
matched_count <- sum(!is.na(h1b_naics_merged$Native))
cat("Records matched to native benchmark:", comma(matched_count),
    "(", percent(matched_count / nrow(h1b_naics_merged), accuracy = 0.1), ")\n")

# --- Step 4: Calculate premium for each worker ---
h1b_naics_premium <- h1b_naics_merged %>%
  filter(!is.na(Native)) %>%
  mutate(
    # Premium = H-1B wage minus native median wage
    personal_premium = INCWAGE - Native,
    # Flag: does this worker earn MORE than comparable natives?
    has_positive_premium = personal_premium > 0
  )

# --- Step 5: Summarize by industry sector ---
# For each sector, calculate premium statistics
industry_summary <- h1b_naics_premium %>%
  group_by(naics_sector, sector_name) %>%
  summarise(
    n_total = n(),
    n_positive = sum(has_positive_premium),
    n_negative = sum(!has_positive_premium),
    share_positive = mean(has_positive_premium),
    share_negative = mean(!has_positive_premium),
    avg_premium = mean(personal_premium),
    median_premium = median(personal_premium),
    avg_salary = mean(INCWAGE),
    .groups = "drop"
  ) %>%
  # Sort by total count (largest industries first)
  arrange(desc(n_total))

cat("Unique industry sectors:", nrow(industry_summary), "\n")

# --- Step 6: Display results ---

# All industries ranked by size
cat("\n--- ALL INDUSTRIES BY H-1B VOLUME ---\n")
cat("(Ranked by total H-1B petitions with valid native benchmark)\n\n")

industry_summary %>%
  mutate(
    Rank = row_number(),
    `Total H-1Bs` = comma(n_total),
    `Share Positive` = percent(share_positive, accuracy = 0.1),
    `Share Negative` = percent(share_negative, accuracy = 0.1),
    `Avg Premium` = dollar(avg_premium),
    `Avg Salary` = dollar(avg_salary)
  ) %>%
  select(Rank, sector_name, `Total H-1Bs`, `Share Positive`, `Share Negative`,
         `Avg Premium`, `Avg Salary`) %>%
  knitr::kable(col.names = c("Rank", "Industry Sector", "Total H-1Bs",
                              "Share Paid Above Natives", "Share Paid Below Natives",
                              "Avg Premium", "Avg Salary"))

# Industries with HIGHEST positive premium rates
cat("\n--- INDUSTRIES WITH HIGHEST SHARE PAID ABOVE NATIVES ---\n")
cat("(Minimum 100 H-1B workers)\n\n")

top_positive_industries <- industry_summary %>%
  filter(n_total >= 100) %>%
  arrange(desc(share_positive)) %>%
  head(15)

top_positive_industries %>%
  mutate(
    Rank = row_number(),
    `Total H-1Bs` = comma(n_total),
    `Share Positive` = percent(share_positive, accuracy = 0.1),
    `Share Negative` = percent(share_negative, accuracy = 0.1),
    `Avg Premium` = dollar(avg_premium)
  ) %>%
  select(Rank, sector_name, `Total H-1Bs`, `Share Positive`, `Share Negative`, `Avg Premium`) %>%
  knitr::kable(col.names = c("Rank", "Industry Sector", "Total H-1Bs",
                              "Share Paid Above", "Share Paid Below", "Avg Premium"))

# Industries with LOWEST positive premium rates (most underpayment)
cat("\n--- INDUSTRIES WITH HIGHEST SHARE PAID BELOW NATIVES ---\n")
cat("(Minimum 100 H-1B workers)\n\n")

top_negative_industries <- industry_summary %>%
  filter(n_total >= 100) %>%
  arrange(share_positive) %>%  # Lowest positive = highest negative
  head(15)

top_negative_industries %>%
  mutate(
    Rank = row_number(),
    `Total H-1Bs` = comma(n_total),
    `Share Positive` = percent(share_positive, accuracy = 0.1),
    `Share Negative` = percent(share_negative, accuracy = 0.1),
    `Avg Premium` = dollar(avg_premium)
  ) %>%
  select(Rank, sector_name, `Total H-1Bs`, `Share Positive`, `Share Negative`, `Avg Premium`) %>%
  knitr::kable(col.names = c("Rank", "Industry Sector", "Total H-1Bs",
                              "Share Paid Above", "Share Paid Below", "Avg Premium"))

# --- Step 7: Visualizations ---

# Chart: Industries by share with positive premium (all industries with 100+ H-1Bs)
industries_for_chart <- industry_summary %>%
  filter(n_total >= 100) %>%
  arrange(desc(share_positive))

ggplot(industries_for_chart,
       aes(x = reorder(str_wrap(sector_name, 35), share_positive),
           y = share_positive)) +
  geom_col(fill = ifp_colors$dark_blue, width = 0.7) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)),
            hjust = -0.1, size = 3) +
  coord_flip() +
  scale_y_continuous(labels = percent, limits = c(0, 1),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = "Share of H-1Bs Paid Above Comparable Natives by Industry",
    subtitle = "Industries with 100+ initial H-1B petitions, FY2022-2024",
    x = NULL,
    y = "Share earning more than comparable natives",
    caption = "Note: 'Comparable natives' = same occupation, education, and age group.\nSource: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b() +
  theme(axis.text.y = element_text(size = 8))

# Chart: Average premium by industry
ggplot(industries_for_chart,
       aes(x = reorder(str_wrap(sector_name, 35), avg_premium),
           y = avg_premium)) +
  geom_col(aes(fill = avg_premium > 0), width = 0.7) +
  geom_text(aes(label = dollar(avg_premium, scale = 0.001, suffix = "k", accuracy = 1),
                hjust = ifelse(avg_premium > 0, -0.1, 1.1)),
            size = 3) +
  coord_flip() +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  scale_y_continuous(labels = dollar_format(scale = 0.001, suffix = "k"),
                     expand = expansion(mult = c(0.15, 0.15))) +
  scale_fill_manual(values = c("TRUE" = ifp_colors$dark_blue, "FALSE" = ifp_colors$red),
                    guide = "none") +
  labs(
    title = "Average H-1B Wage Premium by Industry",
    subtitle = "Industries with 100+ initial H-1B petitions, FY2022-2024",
    x = NULL,
    y = "Average premium vs. comparable natives",
    caption = "Note: 'Comparable natives' = same occupation, education, and age group.\nSource: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b() +
  theme(axis.text.y = element_text(size = 8))

# --- Step 8: Summary statistics ---
cat("\n--- INDUSTRY SUMMARY STATISTICS ---\n\n")

# Overall statistics across all industries
industry_stats <- industry_summary %>%
  filter(n_total >= 100) %>%
  summarise(
    n_industries = n(),
    total_h1bs = sum(n_total),
    weighted_avg_share_positive = weighted.mean(share_positive, w = n_total),
    min_share_positive = min(share_positive),
    max_share_positive = max(share_positive),
    industry_with_highest = sector_name[which.max(share_positive)],
    industry_with_lowest = sector_name[which.min(share_positive)]
  )

cat("Number of industries (100+ H-1Bs):", industry_stats$n_industries, "\n")
cat("Total H-1Bs in these industries:", comma(industry_stats$total_h1bs), "\n")
cat("Weighted avg share with positive premium:",
    percent(industry_stats$weighted_avg_share_positive, accuracy = 0.1), "\n")
cat("Industry with highest positive rate:", industry_stats$industry_with_highest, "\n")
cat("Industry with lowest positive rate:", industry_stats$industry_with_lowest, "\n")

scatter_data %>%
  filter(AGE >19) %>%
  group_by(AGE) %>%
  summarise(avg_premium = mean(personal_premium)) %>%
  ggplot(aes(x = AGE, y = avg_premium))+
  geom_point()

# =============================================================================
# END OF SCRIPT
# =============================================================================
cat("\n\nScript completed successfully!\n")
cat("Report generated on", as.character(Sys.Date()), "\n")

# =============================================================================
# 19. PUMA Controls: Age, Occupation, Education, and PUMA
# =============================================================================

# --- Share with Positive Premium (Full Controls + PUMA) ---
premium_puma <- h1b_merged$age_occ_ed_puma %>%
  calc_share_positive(age_grp) %>%
  filter(!is.na(age_grp), age_grp != "[65,Inf]")

ggplot(premium_puma, aes(x = age_grp, y = share_positive)) +
  geom_col(width = 0.8, fill = ifp_colors$green) +
  geom_text(aes(label = percent(share_positive, accuracy = 1)), vjust = -0.4, size = 3.5) +
  scale_y_continuous(labels = percent, limits = c(0, 1), expand = expansion(mult = c(0, 0.08))) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "H-1B Pay vs. Native with Same Age, Occupation, Education, and PUMA",
    subtitle = "Most granular controls: 5-year age bin + 6-digit SOC + education level + PUMA",
    x = "Age of H-1B recipient",
    y = "Share earning more than comparable natives",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# --- Average Premium (Full Controls + PUMA) ---
avg_puma <- h1b_merged$age_occ_ed_puma %>%
  calc_avg_premium(age_grp) %>%
  filter(!is.na(age_grp), age_grp != "[65,Inf]")

ggplot(avg_puma, aes(x = age_grp, y = avg_premium)) +
  geom_col(width = 0.8, fill = ifp_colors$green) +
  geom_text(aes(
    label = ifelse(avg_premium >= 0, paste0("$", round(avg_premium/1000), "k"),
                   paste0("-$", abs(round(avg_premium/1000)), "k")),
    vjust = ifelse(avg_premium >= 0, -0.35, 1.15)
  ), size = 3) +
  scale_y_continuous(labels = dollar) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "Average H-1B Premium with PUMA Controls",
    subtitle = "Compared to median native with same age, occupation, education, and PUMA",
    x = "Age of H-1B recipient",
    y = "Average wage premium ($)",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b()

# --- Compare All Control Levels ---
comparison_data <- bind_rows(
  h1b_merged$age_only %>% calc_share_positive(age_grp) %>% mutate(control = "Age Only"),
  h1b_merged$ed_age %>% calc_share_positive(age_grp) %>% mutate(control = "Age + Education"),
  h1b_merged$occ_age %>% calc_share_positive(age_grp) %>% mutate(control = "Age + Occupation"),
  h1b_merged$full %>% calc_share_positive(age_grp) %>% mutate(control = "Full (Age + Occ + Ed)"),
  h1b_merged$age_occ_ed_puma %>% calc_share_positive(age_grp) %>% mutate(control = "Full + PUMA")
) %>%
  filter(!is.na(age_grp), age_grp != "[65,Inf]") %>%
  mutate(control = factor(control, levels = c("Age Only", "Age + Education", "Age + Occupation", 
                                               "Full (Age + Occ + Ed)", "Full + PUMA")))

ggplot(comparison_data, aes(x = age_grp, y = share_positive, color = control, group = control)) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2.5) +
  scale_color_manual(values = c("Age Only" = ifp_colors$light_blue,
                                 "Age + Education" = ifp_colors$orange,
                                 "Age + Occupation" = ifp_colors$purple,
                                 "Full (Age + Occ + Ed)" = ifp_colors$dark_blue,
                                 "Full + PUMA" = ifp_colors$green)) +
  scale_y_continuous(labels = percent, limits = c(0, 1)) +
  scale_x_discrete(labels = age_labels) +
  labs(
    title = "Impact of Control Variables on H-1B Wage Premium",
    subtitle = "Share earning more than comparable native-born workers by control configuration",
    x = "Age of H-1B recipient",
    y = "Share with positive premium",
    color = "Control Variables",
    caption = "Source: FY 2022-2024 H-1B data; 2021-2023 ACS via IPUMS"
  ) +
  theme_h1b() +
  theme(legend.position = "bottom")

# --- Overall Summary Statistics for PUMA Control ---
overall_puma <- h1b_merged$age_occ_ed_puma %>%
  filter(H1B == 1, !is.na(Native)) %>%
  summarise(
    n = n(),
    share_positive = mean(INCWAGE > Native),
    avg_premium = mean(INCWAGE - Native),
    median_premium = median(INCWAGE - Native)
  )

cat("\n=== H-1B Premium Statistics with PUMA Controls ===\n")
cat("  Sample size:", comma(overall_puma$n), "\n")
cat("  Share with positive premium:", percent(overall_puma$share_positive, accuracy = 0.1), "\n")
cat("  Average premium:", dollar(overall_puma$avg_premium), "\n")
cat("  Median premium:", dollar(overall_puma$median_premium), "\n")

# --- Summary Table: All Control Levels ---
summary_by_control <- bind_rows(
  h1b_merged$age_only %>% filter(H1B == 1, !is.na(Native)) %>%
    summarise(control = "Age Only", n = n(), share_pos = mean(INCWAGE > Native), 
              avg_prem = mean(INCWAGE - Native)),
  h1b_merged$ed_age %>% filter(H1B == 1, !is.na(Native)) %>%
    summarise(control = "Age + Education", n = n(), share_pos = mean(INCWAGE > Native),
              avg_prem = mean(INCWAGE - Native)),
  h1b_merged$occ_age %>% filter(H1B == 1, !is.na(Native)) %>%
    summarise(control = "Age + Occupation", n = n(), share_pos = mean(INCWAGE > Native),
              avg_prem = mean(INCWAGE - Native)),
  h1b_merged$full %>% filter(H1B == 1, !is.na(Native)) %>%
    summarise(control = "Full (Age + Occ + Ed)", n = n(), share_pos = mean(INCWAGE > Native),
              avg_prem = mean(INCWAGE - Native)),
  h1b_merged$age_occ_ed_puma %>% filter(H1B == 1, !is.na(Native)) %>%
    summarise(control = "Full + PUMA", n = n(), share_pos = mean(INCWAGE > Native),
              avg_prem = mean(INCWAGE - Native))
) %>%
  mutate(
    `Control Variables` = control,
    `Sample Size` = comma(n),
    `Share Positive` = percent(share_pos, accuracy = 0.1),
    `Avg Premium` = dollar(avg_prem)
  ) %>%
  select(`Control Variables`, `Sample Size`, `Share Positive`, `Avg Premium`)

knitr::kable(summary_by_control, caption = "H-1B Wage Premium by Control Configuration")

cat("\nAnalysis complete! All control configurations have been evaluated.\n")
