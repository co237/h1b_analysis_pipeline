#!/usr/bin/env Rscript

# SOC 2010 to SOC 2018 Crosswalk Creation Script
# Maps older SOC 2010 codes (used in FY2021-2022 OFLC files) to SOC 2018 codes
# (used in ACS data) to enable correct Mincer function application
#
# Strategy:
# 1. Use IPUMS OCC code crosswalk to map 2013-2017 OCCSOC → 2018 OCCSOC via OCC codes
# 2. For codes that have 1:1 mapping via OCC codes, use that mapping
# 3. For codes that were split in 2018 (1:many problem), manually map to "best match"
#    - 15113X (Software Developers, agg) → 151252 (Software Developers)
#    - 151134 (Web Developers) → 151254 (Web Developers)
#    - etc.
# 4. This ensures NO duplicate petitions while applying correct Mincer functions
#
# Inputs:
#   - data/raw/OFLC_Wages_2024-25/ALC_Export_FY2021.csv (source of SOC 2010 codes)
#   - Downloads/occ_occsoc_crosswalk_2000_onward (1).xlsx (IPUMS crosswalk)
#   - data/raw/Other Data/acs_occupations.csv (ACS codes)
#
# Output:
#   - data/raw/soc2010_to_soc2018_crosswalk.csv
#
# Author: Claude
# Date: 2026-03-01

library(tidyverse)
library(readxl)

# Load configuration
if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
} else {
  stop("Cannot find config.R")
}

cat("\n")
cat("=============================================================================\n")
cat("SOC 2010 → SOC 2018 Crosswalk Creation Script\n")
cat("=============================================================================\n\n")

# Read IPUMS crosswalk
cat("Reading IPUMS OCC/OCCSOC crosswalk...\n")
ipums_cw_file <- "~/Downloads/occ_occsoc_crosswalk_2000_onward (1).xlsx"

if (!file.exists(ipums_cw_file)) {
  stop("IPUMS crosswalk not found: ", ipums_cw_file)
}

ipums_cw <- read_excel(ipums_cw_file)
cat(sprintf("  - Crosswalk rows: %d\n", nrow(ipums_cw)))

# Extract 2013-2017 codes (SOC 2010)
codes_2013 <- ipums_cw %>%
  filter(!is.na(`2013-2017 ACS/PRCS OCCSOC code`)) %>%
  select(occ_2013 = `2013-2017 ACS/PRCS OCC code`,
         occsoc_2010 = `2013-2017 ACS/PRCS OCCSOC code`) %>%
  mutate(occsoc_2010_compact = str_remove_all(occsoc_2010, "-"))

cat(sprintf("  - 2013-2017 codes (SOC 2010): %d\n", nrow(codes_2013)))

# Extract 2018 codes (SOC 2018)
codes_2018 <- ipums_cw %>%
  filter(!is.na(`2018 Onward ACS/PRCS`)) %>%
  select(occ_2018 = `2018 ACS/PRCS OCC code`,
         occsoc_2018_compact = `2018 Onward ACS/PRCS`) %>%
  mutate(occsoc_2018 = paste0(
    substr(occsoc_2018_compact, 1, 2), "-",
    substr(occsoc_2018_compact, 3, 6)
  ))

cat(sprintf("  - 2018 codes (SOC 2018): %d\n\n", nrow(codes_2018)))

# Join via OCC codes to create base mapping
cat("Mapping SOC 2010 → SOC 2018 via OCC codes...\n")
base_mapping <- codes_2013 %>%
  left_join(codes_2018, by = c("occ_2013" = "occ_2018"))

cat(sprintf("  - Automatic matches via OCC: %d\n", sum(!is.na(base_mapping$occsoc_2018))))
cat(sprintf("  - Codes needing manual mapping: %d\n\n", sum(is.na(base_mapping$occsoc_2018))))

# Manual mappings for codes that were split in 2018
# These map to the "best match" to avoid one-to-many duplication
# Also includes detailed codes (like 15-1132, 15-1133) that IPUMS aggregated (15113X)
cat("Applying manual mappings for split and detailed occupations...\n")

manual_mappings <- tribble(
  ~occsoc_2010_compact, ~occsoc_2018_compact, ~occsoc_2018, ~reason,
  # Aggregated IPUMS codes
  "15113X", "151252", "15-1252", "Software Developers (aggregated) → Software Developers",
  "151134", "151254", "15-1254", "Web Developers → Web Developers (exact match)",
  "151141", "15124X", "15-124X", "Database Administrators → Database Administrators (aggregated)",
  "151199", "151299", "15-1299", "Computer Occupations, All Other → Computer Occupations, All Other",
  # Detailed codes that IPUMS aggregated but exist in OFLC files
  "151132", "151252", "15-1252", "Software Developers, Applications → Software Developers",
  "151133", "151252", "15-1252", "Software Developers, Systems Software → Software Developers",
  "151151", "151230", "15-1230", "Computer User Support Specialists → Computer Support Specialists",
  "151152", "151230", "15-1230", "Computer Network Support Specialists → Computer Support Specialists"
)

cat("\nManual mappings:\n")
for (i in 1:nrow(manual_mappings)) {
  cat(sprintf("  %s → %s (%s)\n",
              manual_mappings$occsoc_2010_compact[i],
              manual_mappings$occsoc_2018[i],
              manual_mappings$reason[i]))
}

# Apply manual mappings to existing codes
result <- base_mapping %>%
  left_join(manual_mappings %>% select(occsoc_2010_compact,
                                       manual_2018_compact = occsoc_2018_compact,
                                       manual_2018 = occsoc_2018),
            by = "occsoc_2010_compact") %>%
  mutate(
    final_occsoc_2018 = coalesce(occsoc_2018, manual_2018),
    final_occsoc_2018_compact = coalesce(occsoc_2018_compact, manual_2018_compact),
    mapping_type = case_when(
      !is.na(manual_2018) ~ "Manual",
      !is.na(occsoc_2018) ~ "Automatic (OCC match)",
      TRUE ~ "Unmatched"
    )
  ) %>%
  select(SOC_2010 = occsoc_2010,
         SOC_2010_compact = occsoc_2010_compact,
         SOC_2018 = final_occsoc_2018,
         SOC_2018_compact = final_occsoc_2018_compact,
         OCC_code = occ_2013,
         Mapping_Type = mapping_type)

# Add detailed codes that don't exist in IPUMS crosswalk
# These are codes that exist in OFLC files but were aggregated in ACS
cat("\nAdding detailed codes not in IPUMS crosswalk...\n")
additional_codes <- manual_mappings %>%
  filter(!occsoc_2010_compact %in% result$SOC_2010_compact) %>%
  mutate(
    SOC_2010 = paste0(substr(occsoc_2010_compact, 1, 2), "-",
                      substr(occsoc_2010_compact, 3, 6)),
    SOC_2010_compact = occsoc_2010_compact,
    SOC_2018 = occsoc_2018,
    SOC_2018_compact = occsoc_2018_compact,
    OCC_code = NA_real_,
    Mapping_Type = "Manual"
  ) %>%
  select(SOC_2010, SOC_2010_compact, SOC_2018, SOC_2018_compact,
         OCC_code, Mapping_Type)

if (nrow(additional_codes) > 0) {
  cat(sprintf("  Adding %d additional codes\n", nrow(additional_codes)))
  for (i in 1:nrow(additional_codes)) {
    cat(sprintf("    %s → %s\n",
                additional_codes$SOC_2010[i],
                additional_codes$SOC_2018[i]))
  }
  result <- bind_rows(result, additional_codes)
}

# Check for one-to-many mappings (should be ZERO)
cat("\n\nChecking for one-to-many mappings...\n")
one_to_many <- result %>%
  filter(!is.na(SOC_2018)) %>%
  group_by(SOC_2010) %>%
  filter(n() > 1) %>%
  arrange(SOC_2010)

if (nrow(one_to_many) > 0) {
  cat("ERROR: Found one-to-many mappings:\n")
  print(one_to_many)
  stop("One-to-many mappings detected! This would duplicate petitions.")
} else {
  cat("  ✓ No one-to-many mappings detected\n")
}

# Print summary statistics
cat("\n\nMapping Results:\n")
cat("=================\n\n")
cat(sprintf("Total SOC 2010 codes: %d\n", nrow(result)))
cat(sprintf("Successfully mapped: %d (%.1f%%)\n",
            sum(!is.na(result$SOC_2018)),
            100 * sum(!is.na(result$SOC_2018)) / nrow(result)))
cat(sprintf("Unmatched: %d (%.1f%%)\n\n",
            sum(is.na(result$SOC_2018)),
            100 * sum(is.na(result$SOC_2018)) / nrow(result)))

# Break down by mapping type
cat("Mapping Type Breakdown:\n")
mapping_summary <- result %>%
  filter(!is.na(SOC_2018)) %>%
  group_by(Mapping_Type) %>%
  summarise(Count = n(), .groups = "drop")

print(mapping_summary, n = Inf)

# Show software developer examples
cat("\n\nSoftware Developer Examples:\n")
cat("=============================\n\n")
sw_examples <- result %>%
  filter(grepl("^151[1-2]", SOC_2010_compact)) %>%
  select(SOC_2010, SOC_2018, Mapping_Type) %>%
  arrange(SOC_2010)

print(sw_examples, n = 30)

# Show unmatched codes if any
if (sum(is.na(result$SOC_2018)) > 0) {
  cat("\n\nUnmatched Codes:\n")
  cat("=================\n\n")
  unmatched <- result %>%
    filter(is.na(SOC_2018)) %>%
    select(SOC_2010, SOC_2010_compact)

  print(unmatched, n = min(20, nrow(unmatched)))

  if (nrow(unmatched) > 20) {
    cat(sprintf("\n... and %d more unmatched codes\n", nrow(unmatched) - 20))
  }
}

# Save the results
output_file <- file.path(data_raw, "soc2010_to_soc2018_crosswalk.csv")
write_csv(result, output_file)

cat("\n\n")
cat("=============================================================================\n")
cat("Results saved to:", output_file, "\n")
cat("=============================================================================\n\n")

cat("This crosswalk maps SOC 2010 codes (FY2021-2022 OFLC) to SOC 2018 codes (ACS).\n")
cat("Use this to match FY2021-2022 OFLC prevailing wages to correct Mincer functions.\n\n")

cat("Columns in output file:\n")
cat("  - SOC_2010: Original SOC 2010 code (with hyphen, e.g., 15-1132)\n")
cat("  - SOC_2010_compact: SOC 2010 code without hyphen (e.g., 151132)\n")
cat("  - SOC_2018: Mapped SOC 2018 code (with hyphen, e.g., 15-1252)\n")
cat("  - SOC_2018_compact: SOC 2018 code without hyphen (e.g., 151252)\n")
cat("  - OCC_code: 4-digit OCC code used for matching\n")
cat("  - Mapping_Type: How the mapping was determined (Automatic/Manual/Unmatched)\n")

cat("\n\nScript completed successfully!\n\n")
