#!/usr/bin/env Rscript

# Three-Stage SOC Crosswalk: FY2021 OFLC → Pre-2018 ACS → Post-2018 ACS
#
# This script creates a crosswalk that maps FY2021 OFLC SOC 2010 codes to
# 2018 ACS OCCSOC codes via the 2013-2017 ACS codes, ensuring each OFLC
# wage level can be matched to the correct Mincer function.
#
# Strategy:
# 1. Extract 2013-2017 ACS OCCSOC codes from IPUMS crosswalk
# 2. Use hierarchical matching (with X/Y wildcards) to match OFLC SOC 2010 → 2013-2017 ACS
# 3. Map 2013-2017 ACS → 2018 ACS via OCC codes
#
# This ensures NO one-to-many mappings while maximizing coverage
#
# Inputs:
#   - data/raw/OFLC_Wages_2024-25/ALC_Export_FY2021.csv (FY2021 OFLC SOC codes)
#   - ~/Downloads/occ_occsoc_crosswalk_2000_onward (1).xlsx (IPUMS crosswalk)
#
# Output:
#   - data/raw/fy2021_oflc_to_acs_crosswalk.csv
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
cat("Three-Stage SOC Crosswalk: FY2021 OFLC → Pre-2018 ACS → Post-2018 ACS\n")
cat("=============================================================================\n\n")

# ============================================================================
# STEP 1: Read IPUMS crosswalk and extract ACS codes
# ============================================================================

cat("STEP 1: Reading IPUMS crosswalk...\n")
ipums_cw_file <- "~/Downloads/occ_occsoc_crosswalk_2000_onward (1).xlsx"

if (!file.exists(ipums_cw_file)) {
  stop("IPUMS crosswalk not found: ", ipums_cw_file)
}

ipums_cw <- read_excel(ipums_cw_file)

# Extract 2013-2017 ACS codes (pre-2018)
acs_2013_2017 <- ipums_cw %>%
  filter(!is.na(`2013-2017 ACS/PRCS OCCSOC code`)) %>%
  select(OCC_2013 = `2013-2017 ACS/PRCS OCC code`,
         OCCSOC_2013 = `2013-2017 ACS/PRCS OCCSOC code`) %>%
  mutate(
    # Create hierarchical aggregations for 2013-2017 codes
    OCCSOC_2013_last1 = paste0(substr(OCCSOC_2013, 1, 5), "0"),
    OCCSOC_2013_last2 = paste0(substr(OCCSOC_2013, 1, 4), "00"),
    OCCSOC_2013_last3 = paste0(substr(OCCSOC_2013, 1, 3), "000")
  )

cat(sprintf("  - 2013-2017 ACS codes: %d\n", nrow(acs_2013_2017)))

# Extract 2018 ACS codes (post-2018)
acs_2018 <- ipums_cw %>%
  filter(!is.na(`2018 Onward ACS/PRCS`)) %>%
  select(OCC_2018 = `2018 ACS/PRCS OCC code`,
         OCCSOC_2018_compact = `2018 Onward ACS/PRCS`) %>%
  mutate(OCCSOC_2018 = paste0(
    substr(OCCSOC_2018_compact, 1, 2), "-",
    substr(OCCSOC_2018_compact, 3, 6)
  ))

cat(sprintf("  - 2018 ACS codes: %d\n\n", nrow(acs_2018)))

# ============================================================================
# STEP 2: Read FY2021 OFLC codes and create hierarchical variants
# ============================================================================

cat("STEP 2: Reading FY2021 OFLC codes...\n")
fy2021_file <- file.path(data_raw, "OFLC_Wages_2024-25", "ALC_Export_FY2021.csv")

if (!file.exists(fy2021_file)) {
  stop("FY2021 OFLC file not found: ", fy2021_file)
}

oflc_2021 <- read_csv(fy2021_file, show_col_types = FALSE)

# Extract unique SOC codes and create hierarchical aggregations
oflc_codes <- oflc_2021 %>%
  distinct(SocCode) %>%
  filter(!is.na(SocCode)) %>%
  arrange(SocCode) %>%
  mutate(
    # Remove hyphen for matching
    SocCode_compact = str_remove_all(SocCode, "-"),

    # Create aggregated codes (for hierarchical matching)
    # XX-XXX0
    Soc_last1 = paste0(substr(SocCode_compact, 1, 5), "0"),
    # XX-XX00
    Soc_last2 = paste0(substr(SocCode_compact, 1, 4), "00"),
    # XX-X000
    Soc_last3 = paste0(substr(SocCode_compact, 1, 3), "000")
  )

cat(sprintf("  - Unique FY2021 OFLC codes: %d\n\n", nrow(oflc_codes)))

# Show examples
cat("Example SOC 2010 codes with hierarchical variants:\n")
examples <- oflc_codes %>%
  filter(grepl("^15-11", SocCode)) %>%
  head(6) %>%
  select(SocCode, SocCode_compact, Soc_last1, Soc_last2, Soc_last3)
print(examples, n = 6)
cat("\n")

# ============================================================================
# STEP 3: Hierarchical matching functions (from match_soc_codes.R)
# ============================================================================

cat("STEP 3: Setting up hierarchical matching...\n\n")

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
find_acs_match_2013_2017 <- function(oflc_row, acs_data) {
  # Try matching with different levels of specificity
  # Order: SocCode_compact (most specific) -> Soc_last1 -> Soc_last2 -> Soc_last3 (most general)

  soc_variants <- c(
    oflc_row$SocCode_compact,
    oflc_row$Soc_last1,
    oflc_row$Soc_last2,
    oflc_row$Soc_last3
  )

  # Try each variant from most to least specific
  for (oflc_variant in soc_variants) {
    if (is.na(oflc_variant)) next

    # Check against all ACS 2013-2017 codes
    for (i in 1:nrow(acs_data)) {
      if (match_soc_codes(oflc_variant, acs_data$OCCSOC_2013[i])) {
        return(list(
          matched = TRUE,
          acs_2013_code = acs_data$OCCSOC_2013[i],
          occ_2013 = acs_data$OCC_2013[i],
          match_level = which(soc_variants == oflc_variant)[1],
          oflc_matched = oflc_variant
        ))
      }
    }
  }

  # If no match found, return NA
  return(list(
    matched = FALSE,
    acs_2013_code = NA,
    occ_2013 = NA,
    match_level = NA,
    oflc_matched = NA
  ))
}

# ============================================================================
# STEP 4: Match FY2021 OFLC → 2013-2017 ACS
# ============================================================================

cat("STEP 4: Matching FY2021 OFLC codes → 2013-2017 ACS codes...\n")
cat("This may take a moment...\n\n")

# Create progress bar
pb <- txtProgressBar(min = 0, max = nrow(oflc_codes), style = 3)

# Match each OFLC code
matches <- vector("list", nrow(oflc_codes))
for (i in 1:nrow(oflc_codes)) {
  matches[[i]] <- find_acs_match_2013_2017(oflc_codes[i, ], acs_2013_2017)
  setTxtProgressBar(pb, i)
}
close(pb)

# Create result dataframe
stage1_result <- oflc_codes %>%
  mutate(
    ACS_2013_OCCSOC = map_chr(matches, ~ ifelse(is.na(.x$acs_2013_code), NA_character_, .x$acs_2013_code)),
    OCC_2013 = map_dbl(matches, ~ ifelse(is.na(.x$occ_2013), NA_real_, .x$occ_2013)),
    Match_Level = map_int(matches, ~ ifelse(is.na(.x$match_level), NA_integer_, .x$match_level)),
    OFLC_Code_Used = map_chr(matches, ~ ifelse(is.na(.x$oflc_matched), NA_character_, .x$oflc_matched)),
    Matched_Stage1 = map_lgl(matches, ~ .x$matched)
  )

cat("\n\nStage 1 Results (OFLC → 2013-2017 ACS):\n")
cat("========================================\n\n")
cat(sprintf("Total OFLC codes: %d\n", nrow(stage1_result)))
cat(sprintf("Matched to 2013-2017 ACS: %d (%.1f%%)\n",
            sum(stage1_result$Matched_Stage1),
            100 * sum(stage1_result$Matched_Stage1) / nrow(stage1_result)))
cat(sprintf("Unmatched: %d (%.1f%%)\n\n",
            sum(!stage1_result$Matched_Stage1),
            100 * sum(!stage1_result$Matched_Stage1) / nrow(stage1_result)))

# ============================================================================
# STEP 5: Map 2013-2017 ACS → 2018 ACS via OCC codes
# ============================================================================

cat("STEP 5: Mapping 2013-2017 ACS → 2018 ACS via OCC codes...\n\n")

# Join to get 2018 codes via automatic OCC matching
stage2_automatic <- stage1_result %>%
  left_join(acs_2018, by = c("OCC_2013" = "OCC_2018"))

cat(sprintf("  Automatic matches via OCC: %d\n", sum(!is.na(stage2_automatic$OCCSOC_2018))))

# Manual mappings for 2013-2017 codes that don't have direct OCC matches in 2018
# These are codes that were restructured/split between vintages
cat("  Applying manual mappings for restructured codes...\n\n")

manual_2013_to_2018 <- tribble(
  ~acs_2013_code, ~acs_2018_code, ~acs_2018_compact, ~reason,
  # Software Developers (aggregated in 2013-2017, split in 2018)
  "15113X", "15-1252", "151252", "Software Developers (agg) → Software Developers",
  # Web Developers
  "151134", "15-1254", "151254", "Web Developers → Web Developers",
  # Database Administrators
  "151141", "15-124X", "15124X", "Database Administrators → Database Administrators (agg)",
  # Computer Occupations, All Other
  "151199", "15-1299", "151299", "Computer Occupations, All Other → Computer Occupations, All Other",
  # Management codes
  "112020", "11-2030", "112030", "Marketing and Sales Managers (aggregated)",
  "113011", "11-3010", "113010", "Administrative Services Managers",
  "119071", "11-9070", "119070", "Facilities Managers",
  "119XXX", "11-91XX", "1191XX", "Other Management Occupations (aggregated)",
  # Financial codes
  "131199", "13-11XX", "1311XX", "Business Operations Specialists (aggregated)",
  "132051", "13-2050", "132050", "Financial Analysts",
  "132099", "13-20XX", "1320XX", "Financial Specialists (aggregated)",
  # Architecture and Engineering
  "171010", "17-1010", "171010", "Architects",
  "173010", "17-301X", "17301X", "Drafters (aggregated)",
  "173020", "17-302X", "17302X", "Engineering Technicians (aggregated)",
  # Life/Physical/Social Science
  "192040", "19-204X", "19204X", "Environmental Scientists (aggregated)",
  "193030", "19-303X", "19303X", "Psychologists (aggregated)",
  "1940XX", "19-40XX", "1940XX", "Life Scientists (aggregated)",
  "1940YY", "19-40YY", "1940YY", "Life Scientists (aggregated)",
  # Legal
  "211010", "21-109X", "21109X", "Lawyers (aggregated)",
  "211020", "23-1020", "231020", "Paralegals",
  # Education
  "232090", "25-2050", "252050", "Special Education Teachers",
  "251000", "25-1000", "251000", "Postsecondary Teachers (aggregated)",
  "253000", "25-30XX", "2530XX", "Other Teachers and Instructors (aggregated)",
  "254021", "25-4020", "254020", "Librarians",
  "259041", "25-9040", "259040", "Teacher Assistants",
  "2590XX", "25-90XX", "2590XX", "Other Education, Training, and Library Occupations (aggregated)",
  # Arts, Design, Entertainment, Sports, Media
  "271020", "27-102X", "27102X", "Designers (aggregated)",
  "272020", "27-2020", "272020", "Athletes, Coaches, Umpires (aggregated)",
  "272040", "27-2040", "272040", "Musicians, Singers, and Related Workers (aggregated)",
  "272099", "27-2099", "272099", "Entertainers and Performers, Sports and Related Workers, All Other",
  "273010", "27-3010", "273010", "Announcers (aggregated)",
  "273090", "27-3090", "273090", "Miscellaneous Media and Communication Workers (aggregated)",
  "2740XX", "27-40XX", "2740XX", "Broadcast and Sound Engineering Technicians and Radio Operators (aggregated)",
  # Healthcare Practitioners
  "291060", "29-1060", "291060", "Physicians and Surgeons (aggregated)",
  "292030", "29-203X", "29203X", "Diagnostic Related Technologists and Technicians (aggregated)",
  "292041", "29-2040", "292040", "Emergency Medical Technicians and Paramedics (aggregated)",
  "292050", "29-205X", "29205X", "Health Diagnosing and Treating Practitioner Support Technicians (aggregated)",
  "292071", "29-2070", "292070", "Health Technologists and Technicians (aggregated)",
  "292090", "29-2090", "292090", "Miscellaneous Health Technologists and Technicians (aggregated)",
  "299000", "29-9000", "299000", "Other Healthcare Practitioners and Technical Occupations (aggregated)",
  # Healthcare Support
  "311010", "31-1010", "311010", "Nursing, Psychiatric, and Home Health Aides (aggregated)",
  # Protective Service
  "331016", "33-1010", "331010", "First-Line Supervisors of Correctional Officers",
  "331099", "33-1099", "331099", "First-Line Supervisors of Protective Service Workers, All Other",
  "339093", "33-909X", "33909X", "Protective Service Workers, All Other (aggregated)",
  # Food Preparation and Serving
  "353020", "35-3020", "353020", "Fast Food and Counter Workers (aggregated)",
  # Building and Grounds Cleaning and Maintenance
  "373010", "37-301X", "37301X", "Grounds Maintenance Workers (aggregated)",
  # Personal Care and Service
  "393010", "39-3010", "393010", "Animal Care and Service Workers (aggregated)",
  "393090", "39-3090", "393090", "Miscellaneous Entertainment Attendants and Related Workers (aggregated)",
  "395090", "39-509X", "39509X", "Personal Appearance Workers (aggregated)",
  "399000", "39-9000", "399000", "Other Personal Care and Service Workers (aggregated)",
  # Sales
  "413010", "41-3010", "413010", "Sales Representatives, Services (aggregated)",
  "414012", "41-4012", "414012", "Sales Representatives, Wholesale and Manufacturing",
  # Office and Administrative Support
  "431020", "43-1020", "431020", "First-Line Supervisors of Office and Administrative Support Workers (aggregated)",
  "434051", "43-4051", "434051", "Customer Service Representatives",
  "439041", "43-9041", "439041", "Insurance Claims and Policy Processing Clerks",
  "439061", "43-9061", "439061", "Office Clerks, General",
  "439XXX", "43-9XXX", "439XXX", "Other Office and Administrative Support Workers (aggregated)",
  # Construction and Extraction
  "472XXX", "47-2XXX", "472XXX", "Construction Trades Workers (aggregated)",
  "474060", "47-4060", "474060", "Cement Masons, Concrete Finishers, and Terrazzo Workers (aggregated)",
  "475040", "47-5040", "475040", "Mining Machine Operators (aggregated)",
  # Installation, Maintenance, and Repair
  "491011", "49-1011", "491011", "First-Line Supervisors of Mechanics, Installers, and Repairers",
  "492090", "49-209X", "49209X", "Miscellaneous Vehicle and Mobile Equipment Mechanics, Installers, and Repairers (aggregated)",
  "499020", "49-9020", "499020", "Electrical and Electronics Repairers (aggregated)",
  "499050", "49-9050", "499050", "Control and Valve Installers and Repairers (aggregated)",
  # Production
  "512090", "51-2090", "512090", "Miscellaneous Assemblers and Fabricators (aggregated)",
  "514030", "51-403X", "51403X", "Machinists (aggregated)",
  "514120", "51-4120", "514120", "Welding, Soldering, and Brazing Workers (aggregated)",
  "515090", "51-5090", "515090", "Miscellaneous Printing Workers (aggregated)",
  "517XXX", "51-7XXX", "517XXX", "Woodworkers (aggregated)",
  "518030", "51-8030", "518030", "Water and Wastewater Treatment Plant and System Operators (aggregated)",
  "519120", "51-9120", "519120", "Coating, Painting, and Spraying Machine Setters, Operators, and Tenders (aggregated)",
  "519190", "51-9190", "519190", "Miscellaneous Production Workers (aggregated)",
  # Transportation and Material Moving
  "533020", "53-3020", "533020", "Bus Drivers (aggregated)",
  "533050", "53-3050", "533050", "Taxi Drivers and Chauffeurs (aggregated)",
  "537060", "53-7060", "537060", "Helpers--Production Workers (aggregated)"
)

cat("Manual mappings for 2013-2017 → 2018:\n")
for (i in 1:nrow(manual_2013_to_2018)) {
  cat(sprintf("  %s → %s (%s)\n",
              manual_2013_to_2018$acs_2013_code[i],
              manual_2013_to_2018$acs_2018_code[i],
              manual_2013_to_2018$reason[i]))
}
cat("\n")

# Apply manual mappings
final_result <- stage2_automatic %>%
  left_join(manual_2013_to_2018 %>%
              select(ACS_2013_OCCSOC = acs_2013_code,
                     manual_2018 = acs_2018_code,
                     manual_2018_compact = acs_2018_compact),
            by = "ACS_2013_OCCSOC") %>%
  mutate(
    OCCSOC_2018_final = coalesce(OCCSOC_2018, manual_2018),
    OCCSOC_2018_compact_final = coalesce(OCCSOC_2018_compact, manual_2018_compact),
    Mapping_Type_Stage2 = case_when(
      !is.na(manual_2018) ~ "Manual",
      !is.na(OCCSOC_2018) ~ "Automatic (OCC)",
      TRUE ~ "Unmatched"
    ),
    Matched_Stage2 = !is.na(OCCSOC_2018_final),
    Final_Match = Matched_Stage1 & Matched_Stage2
  ) %>%
  # Replace with final values
  mutate(
    OCCSOC_2018 = OCCSOC_2018_final,
    OCCSOC_2018_compact = OCCSOC_2018_compact_final
  ) %>%
  select(-OCCSOC_2018_final, -OCCSOC_2018_compact_final, -manual_2018, -manual_2018_compact)

cat("Stage 2 Results (2013-2017 ACS → 2018 ACS):\n")
cat("============================================\n\n")
cat(sprintf("Codes matched in Stage 1: %d\n", sum(final_result$Matched_Stage1)))
cat(sprintf("Successfully mapped to 2018: %d (%.1f%%)\n",
            sum(final_result$Final_Match),
            100 * sum(final_result$Final_Match) / sum(final_result$Matched_Stage1)))
cat(sprintf("  - Automatic (OCC match): %d\n",
            sum(final_result$Mapping_Type_Stage2 == "Automatic (OCC)", na.rm = TRUE)))
cat(sprintf("  - Manual mappings: %d\n",
            sum(final_result$Mapping_Type_Stage2 == "Manual", na.rm = TRUE)))
cat(sprintf("Lost in Stage 2: %d\n\n",
            sum(final_result$Matched_Stage1 & !final_result$Matched_Stage2)))

# ============================================================================
# STEP 6: Check for one-to-many mappings
# ============================================================================

cat("STEP 6: Checking for one-to-many mappings...\n")

one_to_many <- final_result %>%
  filter(Final_Match) %>%
  group_by(SocCode) %>%
  filter(n() > 1) %>%
  arrange(SocCode)

if (nrow(one_to_many) > 0) {
  cat("ERROR: Found one-to-many mappings:\n")
  print(one_to_many)
  stop("One-to-many mappings detected! This would duplicate petitions.")
} else {
  cat("  ✓ No one-to-many mappings detected\n\n")
}

# ============================================================================
# STEP 7: Summary and save results
# ============================================================================

cat("Final Results:\n")
cat("==============\n\n")
cat(sprintf("Total FY2021 OFLC codes: %d\n", nrow(final_result)))
cat(sprintf("Successfully mapped to 2018 ACS: %d (%.1f%%)\n",
            sum(final_result$Final_Match),
            100 * sum(final_result$Final_Match) / nrow(final_result)))
cat(sprintf("Unmatched: %d (%.1f%%)\n\n",
            sum(!final_result$Final_Match),
            100 * sum(!final_result$Final_Match) / nrow(final_result)))

# Show software developer examples
cat("Software Developer Examples:\n")
cat("==============================\n\n")
sw_examples <- final_result %>%
  filter(grepl("^15-11", SocCode) | grepl("^15-12", SocCode)) %>%
  select(SocCode, ACS_2013_OCCSOC, OCCSOC_2018, Match_Level) %>%
  arrange(SocCode)

print(sw_examples, n = 20)

# Show unmatched codes if any
if (sum(!final_result$Final_Match) > 0) {
  cat("\n\nUnmatched Codes (first 20):\n")
  cat("============================\n\n")
  unmatched <- final_result %>%
    filter(!Final_Match) %>%
    select(SocCode, ACS_2013_OCCSOC, Matched_Stage1, Matched_Stage2)

  print(unmatched, n = 20)

  if (nrow(unmatched) > 20) {
    cat(sprintf("\n... and %d more unmatched codes\n", nrow(unmatched) - 20))
  }
}

# Select final columns and save
output <- final_result %>%
  select(
    OFLC_SOC_2010 = SocCode,
    OFLC_SOC_2010_compact = SocCode_compact,
    ACS_2013_OCCSOC,
    ACS_2018_OCCSOC = OCCSOC_2018,
    ACS_2018_OCCSOC_compact = OCCSOC_2018_compact,
    OCC_code = OCC_2013,
    Match_Level,
    OFLC_Code_Used,
    Stage2_Mapping_Type = Mapping_Type_Stage2,
    Matched = Final_Match
  )

output_file <- file.path(data_raw, "fy2021_oflc_to_acs_crosswalk.csv")
write_csv(output, output_file)

cat("\n\n")
cat("=============================================================================\n")
cat("Results saved to:", output_file, "\n")
cat("=============================================================================\n\n")

cat("This crosswalk maps FY2021 OFLC SOC 2010 codes to 2018 ACS OCCSOC codes\n")
cat("via 2013-2017 ACS codes, ensuring correct Mincer function application.\n\n")

cat("Columns in output file:\n")
cat("  - OFLC_SOC_2010: Original FY2021 SOC code (e.g., 15-1132)\n")
cat("  - OFLC_SOC_2010_compact: Without hyphen (e.g., 151132)\n")
cat("  - ACS_2013_OCCSOC: Matched 2013-2017 ACS code (e.g., 15113X)\n")
cat("  - ACS_2018_OCCSOC: Final 2018 ACS code (e.g., 15-1252)\n")
cat("  - ACS_2018_OCCSOC_compact: Without hyphen (e.g., 151252)\n")
cat("  - OCC_code: 4-digit OCC code used for Stage 2 mapping\n")
cat("  - Match_Level: Hierarchical match level in Stage 1 (1=exact, 4=most general)\n")
cat("  - OFLC_Code_Used: Which OFLC variant was matched in Stage 1\n")
cat("  - Stage2_Mapping_Type: How Stage 2 was mapped (Automatic/Manual/Unmatched)\n")
cat("  - Matched: Boolean indicating successful end-to-end mapping\n")

cat("\n\nScript completed successfully!\n\n")
