#!/usr/bin/env Rscript

# SOC Code Matching Script - FY2021 OFLC to ACS
# Matches OFLC SOC codes from FY2021 wage files with ACS OCCSOC codes
# FY2021 uses SOC 2010 codes, while current files use SOC 2018
#
# This script creates a crosswalk for the older SOC 2010 codes
# used in FY2021 and FY2022 OFLC files
#
# Inputs:
#   - data/raw/OFLC_Wages_2024-25/ALC_Export_FY2021.csv (OFLC SOC 2010 codes)
#   - data/raw/Other Data/acs_occupations.csv (ACS codes)
#
# Output:
#   - data/raw/oflc_acs_matched_fy2021_soc2010.csv
#
# Author: Claude
# Date: 2026-03-01

library(tidyverse)

# Load configuration
if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
} else {
  stop("Cannot find config.R")
}

# Function to check if an OFLC SOC code matches an ACS OCCSOC code
# ACS codes can contain X or Y as wildcards (representing any digit)
match_soc_codes <- function(oflc_code, acs_code) {
  # Handle NA values
  if (is.na(oflc_code) || is.na(acs_code)) {
    return(FALSE)
  }

  # Convert both to character and remove any whitespace
  oflc_code <- as.character(oflc_code) %>% str_trim()
  acs_code <- as.character(acs_code) %>% str_trim()

  # If codes are identical, return TRUE
  if (oflc_code == acs_code) {
    return(TRUE)
  }

  # Create a regex pattern from the ACS code
  # Replace X or Y with a digit pattern [0-9]
  pattern <- acs_code %>%
    str_replace_all("[XY]", "[0-9]") %>%
    paste0("^", ., "$")  # Add anchors for exact match

  # Check if OFLC code matches the pattern
  return(str_detect(oflc_code, pattern))
}

# Function to find the best ACS match for an OFLC SOC code
# Uses hierarchical matching: tries exact match first, then progressively
# more aggregated versions
find_acs_match <- function(oflc_row, acs_data) {
  # Try matching with different levels of specificity
  # Order: SocCode (most specific) -> Soc_last1 -> Soc_last2 -> Soc_last3 (most general)

  soc_variants <- c(
    oflc_row$SocCode,
    oflc_row$Soc_last1,
    oflc_row$Soc_last2,
    oflc_row$Soc_last3
  )

  # Try each variant from most to least specific
  for (oflc_variant in soc_variants) {
    if (is.na(oflc_variant)) next

    # Check against all ACS codes
    for (i in 1:nrow(acs_data)) {
      if (match_soc_codes(oflc_variant, acs_data$OCCSOC[i])) {
        return(list(
          matched = TRUE,
          acs_code = acs_data$OCCSOC[i],
          match_level = which(soc_variants == oflc_variant)[1],
          oflc_matched = oflc_variant
        ))
      }
    }
  }

  # If no match found, return NA
  return(list(
    matched = FALSE,
    acs_code = NA,
    match_level = NA,
    oflc_matched = NA
  ))
}

# Main script
cat("\n")
cat("=============================================================================\n")
cat("SOC Code Matching Script - FY2021 (SOC 2010) to ACS\n")
cat("=============================================================================\n\n")

# Read the FY2021 OFLC file and extract unique SOC codes
cat("Reading FY2021 OFLC wage file...\n")
oflc_2021_file <- file.path(data_raw, "OFLC_Wages", "ALC_Export_FY2021.csv")

if (!file.exists(oflc_2021_file)) {
  stop("FY2021 OFLC file not found: ", oflc_2021_file)
}

oflc_2021_raw <- read_csv(oflc_2021_file, show_col_types = FALSE)

# Extract unique SOC codes
oflc_data <- oflc_2021_raw %>%
  distinct(SocCode) %>%
  arrange(SocCode)

cat(sprintf("  - Unique SOC codes in FY2021 OFLC: %d\n", nrow(oflc_data)))

# Create hierarchical aggregation columns
# Soc_last1: Replace last 1 digit with 0 (e.g., 13-2011 → 13-2010)
# Soc_last2: Replace last 2 digits with 0 (e.g., 13-2011 → 13-2000)
# Soc_last3: Replace last 3 digits with 0 (e.g., 13-2011 → 13-2000)

oflc_data <- oflc_data %>%
  mutate(
    # Extract parts of the SOC code
    major = substr(SocCode, 1, 2),      # First 2 digits (major group)
    minor_full = substr(SocCode, 4, 7),  # Last 4 digits after hyphen

    # Create aggregated codes
    Soc_last1 = paste0(major, "-", substr(minor_full, 1, 3), "0"),  # XX-XXX0
    Soc_last2 = paste0(major, "-", substr(minor_full, 1, 2), "00"), # XX-XX00
    Soc_last3 = paste0(major, "-", substr(minor_full, 1, 1), "000") # XX-X000
  ) %>%
  select(-major, -minor_full)

cat("  ✓ Created hierarchical aggregation columns\n\n")

# Show some examples
cat("Example SOC 2010 codes from FY2021:\n")
examples <- oflc_data %>%
  filter(grepl("^15-11", SocCode)) %>%
  head(6) %>%
  select(SocCode, Soc_last1, Soc_last2, Soc_last3)
print(examples, n = 6)
cat("\n")

# Read ACS occupation codes
cat("Reading ACS occupation codes...\n")
acs_file <- file.path(data_raw, "Other_Data", "acs_occupations.csv")

if (!file.exists(acs_file)) {
  stop("ACS file not found: ", acs_file, "\n",
       "Please ensure acs_occupations.csv is in data/raw/Other_Data/")
}

acs_data <- read_csv(acs_file, show_col_types = FALSE)
cat(sprintf("  - ACS occupations: %d\n\n", nrow(acs_data)))

# Perform matching
cat("Performing hierarchical SOC code matching...\n")
cat("Matching SOC 2010 codes (FY2021) → ACS codes\n")
cat("This may take a moment...\n\n")

# Create a progress indicator
pb <- txtProgressBar(min = 0, max = nrow(oflc_data), style = 3)

# Match each OFLC code
matches <- vector("list", nrow(oflc_data))
for (i in 1:nrow(oflc_data)) {
  matches[[i]] <- find_acs_match(oflc_data[i, ], acs_data)
  setTxtProgressBar(pb, i)
}
close(pb)

# Create result dataframe
result <- oflc_data %>%
  mutate(
    ACS_OCCSOC = map_chr(matches, ~ .x$acs_code),
    Match_Level = map_int(matches, ~ ifelse(is.na(.x$match_level), NA_integer_, .x$match_level)),
    OFLC_Code_Used = map_chr(matches, ~ ifelse(is.na(.x$oflc_matched), NA_character_, .x$oflc_matched)),
    Matched = map_lgl(matches, ~ .x$matched)
  )

# Create match level labels
match_labels <- c(
  "1" = "Exact (SocCode)",
  "2" = "Aggregated Level 1 (Soc_last1)",
  "3" = "Aggregated Level 2 (Soc_last2)",
  "4" = "Aggregated Level 3 (Soc_last3)"
)

result <- result %>%
  mutate(Match_Level_Description = match_labels[as.character(Match_Level)])

# Print summary statistics
cat("\n\nMatching Results:\n")
cat("=================\n\n")
cat(sprintf("Total OFLC SOC 2010 codes: %d\n", nrow(result)))
cat(sprintf("Successfully matched: %d (%.1f%%)\n",
            sum(result$Matched),
            100 * sum(result$Matched) / nrow(result)))
cat(sprintf("Unmatched: %d (%.1f%%)\n\n",
            sum(!result$Matched),
            100 * sum(!result$Matched) / nrow(result)))

# Break down by match level
cat("Match Level Breakdown:\n")
match_summary <- result %>%
  filter(Matched) %>%
  group_by(Match_Level_Description) %>%
  summarise(Count = n(), .groups = "drop") %>%
  arrange(Match_Level_Description)

print(match_summary, n = Inf)

# Show examples of software developer codes (these use SOC 2010)
cat("\n\nSoftware Developer Codes (SOC 2010 → ACS):\n")
cat("===========================================\n\n")
sw_examples <- result %>%
  filter(grepl("^15-11[23]", SocCode)) %>%
  select(SocCode, ACS_OCCSOC, Match_Level_Description)

print(sw_examples, n = Inf)

cat("\nNote: These are SOC 2010 codes used in FY2021-2022:\n")
cat("  15-1131 = Computer Programmers\n")
cat("  15-1132 = Software Developers, Applications\n")
cat("  15-1133 = Software Developers, Systems Software\n")
cat("  15-1134 = Web Developers\n\n")

# Show some examples of matches at each level
cat("\n\nExample Matches:\n")
cat("================\n\n")

for (level in 1:4) {
  examples <- result %>%
    filter(Match_Level == level) %>%
    select(SocCode, ACS_OCCSOC, OFLC_Code_Used, Match_Level_Description) %>%
    head(3)

  if (nrow(examples) > 0) {
    cat(sprintf("\n%s:\n", match_labels[as.character(level)]))
    print(examples, n = Inf)
  }
}

# Show unmatched codes if any
if (sum(!result$Matched) > 0) {
  cat("\n\nUnmatched OFLC Codes:\n")
  cat("=====================\n\n")
  unmatched <- result %>%
    filter(!Matched) %>%
    select(SocCode, Soc_last1, Soc_last2, Soc_last3)
  print(unmatched, n = min(20, nrow(unmatched)))

  if (nrow(unmatched) > 20) {
    cat(sprintf("\n... and %d more unmatched codes\n", nrow(unmatched) - 20))
  }
}

# Manually adjust codes that don't match
# These are special cases where ACS aggregates certain detailed codes
result <- result %>%
  mutate(ACS_OCCSOC = case_when(SocCode == "29-1221" ~ "29-1210",
                                SocCode == "29-1222" ~ "29-1210",
                                SocCode == "29-1223" ~ "29-1210",
                                SocCode == "29-1224" ~ "29-1210",
                                SocCode == "29-1229" ~ "29-1210",
                                TRUE ~ ACS_OCCSOC),
         Match_Level_Description = case_when(SocCode %in% c("29-1221","29-1222","29-1223","29-1224","29-1229") ~ "Manual",
                                            TRUE ~ Match_Level_Description),
         Matched = ifelse(Match_Level_Description == "Manual", TRUE, Matched))

# Save the results
output_file <- file.path(data_raw, "oflc_acs_matched_fy2021_soc2010.csv")
write_csv(result, output_file)

cat("\n\n")
cat("=============================================================================\n")
cat("Results saved to:", output_file, "\n")
cat("=============================================================================\n\n")

cat("This crosswalk maps SOC 2010 codes (FY2021-2022) to ACS codes.\n")
cat("For SOC 2018 codes (FY2023+), use the standard oflc_acs_matched.csv file.\n\n")

cat("Columns in output file:\n")
cat("  - SocCode: OFLC SOC 2010 code (6-digit format)\n")
cat("  - Soc_last1, Soc_last2, Soc_last3: Aggregated OFLC codes\n")
cat("  - ACS_OCCSOC: Matched ACS occupation code\n")
cat("  - Match_Level: Level at which match was found (1=most specific, 4=most general)\n")
cat("  - Match_Level_Description: Human-readable description of match level\n")
cat("  - OFLC_Code_Used: Which OFLC code variant was used for the match\n")
cat("  - Matched: Boolean indicating if a match was found\n")

cat("\n\nScript completed successfully!\n\n")
