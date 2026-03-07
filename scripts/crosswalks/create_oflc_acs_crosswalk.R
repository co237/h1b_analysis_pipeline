#!/usr/bin/env Rscript

# SOC Code Matching Script
# Matches OFLC SOC codes with ACS OCCSOC codes
# Handles hierarchical matching with X and Y wildcards in ACS codes
#
# This script creates the oflc_acs_matched.csv file which is then used
# to create the final occupation_oflc_to_acs_crosswalk.csv
#
# Inputs:
#   - data/raw/Other Data/oflc_occupations.csv
#   - data/raw/Other Data/acs_occupations.csv
#
# Output:
#   - data/raw/oflc_acs_matched.csv
#
# Author: Claude
# Date: 2026-02-04

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
cat("SOC Code Matching Script\n")
cat("=============================================================================\n\n")

# Read the data files
cat("Reading data files...\n")
oflc_file <- file.path(data_raw, "Other Data", "oflc_occupations.csv")
acs_file <- file.path(data_raw, "Other Data", "acs_occupations.csv")

# Check if files exist
if (!file.exists(oflc_file)) {
  stop("OFLC file not found: ", oflc_file, "\n",
       "Please ensure oflc_occupations.csv is in data/raw/Other Data/")
}
if (!file.exists(acs_file)) {
  stop("ACS file not found: ", acs_file, "\n",
       "Please ensure acs_occupations.csv is in data/raw/Other Data/")
}

oflc_data <- read_csv(oflc_file, show_col_types = FALSE)
acs_data <- read_csv(acs_file, show_col_types = FALSE)

cat(sprintf("  - OFLC occupations: %d\n", nrow(oflc_data)))
cat(sprintf("  - ACS occupations: %d\n\n", nrow(acs_data)))

# Perform matching
cat("Performing hierarchical SOC code matching...\n")
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
cat(sprintf("Total OFLC codes: %d\n", nrow(result)))
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

# Manually adjust the codes that don't match
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
output_file <- file.path(data_raw, "oflc_acs_matched.csv")
write_csv(result, output_file)

cat("\n\n")
cat("=============================================================================\n")
cat("Results saved to:", output_file, "\n")
cat("=============================================================================\n\n")

cat("Columns in output file:\n")
cat("  - SocCode: Original OFLC SOC code\n")
cat("  - Soc_last1, Soc_last2, Soc_last3: Aggregated OFLC codes\n")
cat("  - ACS_OCCSOC: Matched ACS occupation code\n")
cat("  - Match_Level: Level at which match was found (1=most specific, 4=most general)\n")
cat("  - Match_Level_Description: Human-readable description of match level\n")
cat("  - OFLC_Code_Used: Which OFLC code variant was used for the match\n")
cat("  - Matched: Boolean indicating if a match was found\n")

cat("\n\nScript completed successfully!\n\n")
