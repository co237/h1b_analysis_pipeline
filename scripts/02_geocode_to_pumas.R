# ============================================================================
# Geocode H-1B Petition Data to PUMAs (Public Use Microdata Areas)
# ============================================================================
#
# This script assigns 2020 and 2010 vintage PUMAs to H-1B petition data based
# on worksite ZIP codes using Census Bureau crosswalk files.
#
# Approach:
#   1. Download Census 2020 ZCTA-to-PUMA relationship file
#   2. Download Census 2020 PUMA-to-2010 PUMA relationship file
#   3. Process crosswalks to assign PUMA with largest geographic overlap
#   4. Join to H-1B data using worksite ZIP codes
#
# Sources:
#   - Census 2020 ZCTA-PUMA: https://www2.census.gov/geo/docs/maps-data/data/rel2020/puma520/
#   - Census Relationship Files: https://www.census.gov/geographies/reference-files/time-series/geo/relationship-files.2020.html
# ============================================================================

# Load configuration
if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
} else {
  stop("Cannot find config.R. Please make sure your working directory is set to the project root")
}

library(dplyr)
library(readr)
library(stringr)
library(tidyr)

########################################################################################
# CONFIGURATION
########################################################################################

# Input file path (output from data cleaning step)
input_file <- cleaned_h1b_file

# Output file path
output_file <- h1b_with_pumas_file

# Census crosswalk URLs
zcta_puma_2020_url <- "https://www2.census.gov/geo/docs/maps-data/data/rel2020/puma520/tab20_puma520_zcta520_natl.txt"
puma_2020_to_2010_url <- "https://www2.census.gov/geo/docs/maps-data/data/rel2020/puma520/tab20_puma520_puma510_natl.txt"

# Local cache paths (from config)
cache_dir <- census_crosswalks_dir

########################################################################################
# HELPER FUNCTIONS
########################################################################################

#' Download file if not already cached
download_if_needed <- function(url, local_path) {
  if (!file.exists(local_path)) {
    message("Downloading: ", basename(url))
    dir.create(dirname(local_path), showWarnings = FALSE, recursive = TRUE)
    download.file(url, local_path, mode = "wb")
  } else {
    message("Using cached: ", basename(local_path))
  }
  return(local_path)
}

#' Clean and standardize ZIP codes to 5 digits
clean_zip <- function(zip) {
  # Remove quotes, whitespace, and take first 5 characters
  zip_clean <- str_trim(zip)
  zip_clean <- str_replace_all(zip_clean, '"', '')
  zip_clean <- str_sub(zip_clean, 1, 5)
  # Pad with leading zeros if needed
  zip_clean <- str_pad(zip_clean, width = 5, side = "left", pad = "0")
  # Set invalid ZIPs to NA
  zip_clean <- ifelse(str_detect(zip_clean, "^[0-9]{5}$"), zip_clean, NA_character_)
  return(zip_clean)
}

########################################################################################
# STEP 1: Download and Process 2020 ZCTA-to-PUMA Crosswalk
########################################################################################

message("\n=== Step 1: Processing 2020 ZCTA-to-PUMA Crosswalk ===\n")

# Download the crosswalk file
zcta_puma_file <- download_if_needed(
  zcta_puma_2020_url,
  paste0(cache_dir, "tab20_puma520_zcta520_natl.txt")
)

# Read the crosswalk (pipe-delimited)
zcta_puma_raw <- read_delim(
  zcta_puma_file,
  delim = "|",
  col_types = cols(.default = col_character()),
  show_col_types = FALSE
)

message("Raw ZCTA-PUMA crosswalk rows: ", nrow(zcta_puma_raw))

# Process: Extract relevant columns and calculate allocation factor
# AREALAND_PART represents the overlapping land area
zcta_puma_2020 <- zcta_puma_raw %>%
  # Filter to rows with valid PUMA codes (exclude territories without PUMAs)
  filter(!is.na(GEOID_PUMA5_20) & GEOID_PUMA5_20 != "") %>%
  # Select and rename relevant columns
  select(
    ZCTA5 = GEOID_ZCTA5_20,
    PUMA_2020 = GEOID_PUMA5_20,
    PUMA_2020_NAME = NAMELSAD_PUMA5_20,
    AREALAND_PART
  ) %>%
  # Convert area to numeric for comparison
  mutate(AREALAND_PART = as.numeric(AREALAND_PART)) %>%
  # For each ZCTA, keep only the PUMA with the largest land area overlap
  group_by(ZCTA5) %>%
  slice_max(order_by = AREALAND_PART, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  # Clean up - drop the area column
  select(ZCTA5, PUMA_2020, PUMA_2020_NAME)

message("Unique ZCTAs with 2020 PUMA assignments: ", n_distinct(zcta_puma_2020$ZCTA5))
message("Unique 2020 PUMAs: ", n_distinct(zcta_puma_2020$PUMA_2020))

########################################################################################
# STEP 2: Download and Process 2020-to-2010 PUMA Crosswalk
########################################################################################

message("\n=== Step 2: Processing 2020-to-2010 PUMA Crosswalk ===\n")

# Download the crosswalk file
puma_xwalk_file <- download_if_needed(
  puma_2020_to_2010_url,
  paste0(cache_dir, "tab20_puma520_puma510_natl.txt")
)

# Read the crosswalk
puma_xwalk_raw <- read_delim(
  puma_xwalk_file,
  delim = "|",
  col_types = cols(.default = col_character()),
  show_col_types = FALSE
)

message("Raw 2020-to-2010 PUMA crosswalk rows: ", nrow(puma_xwalk_raw))

# Process: For each 2020 PUMA, find the 2010 PUMA with largest overlap
puma_2020_to_2010 <- puma_xwalk_raw %>%
  # Filter to rows with valid PUMA codes
  filter(
    !is.na(GEOID_PUMA5_20) & GEOID_PUMA5_20 != "",
    !is.na(GEOID_PUMA5_10) & GEOID_PUMA5_10 != ""
  ) %>%
  # Select relevant columns
  select(
    PUMA_2020 = GEOID_PUMA5_20,
    PUMA_2010 = GEOID_PUMA5_10,
    PUMA_2010_NAME = NAMELSAD_PUMA5_10,
    AREALAND_PART
  ) %>%
  # Convert area to numeric
  mutate(AREALAND_PART = as.numeric(AREALAND_PART)) %>%
  # For each 2020 PUMA, keep only the 2010 PUMA with largest overlap
  group_by(PUMA_2020) %>%
  slice_max(order_by = AREALAND_PART, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  # Clean up
  select(PUMA_2020, PUMA_2010, PUMA_2010_NAME)

message("Unique 2020 PUMAs with 2010 assignments: ", n_distinct(puma_2020_to_2010$PUMA_2020))
message("Unique 2010 PUMAs: ", n_distinct(puma_2020_to_2010$PUMA_2010))

########################################################################################
# STEP 3: Create Combined ZIP-to-PUMA Crosswalk
########################################################################################

message("\n=== Step 3: Creating Combined Crosswalk ===\n")

# Join to create ZIP -> 2020 PUMA -> 2010 PUMA mapping
zip_to_puma <- zcta_puma_2020 %>%
  left_join(puma_2020_to_2010, by = "PUMA_2020") %>%
  # Rename ZCTA5 to ZIP for clarity (they're effectively the same for matching)
  rename(ZIP5 = ZCTA5)

message("Final crosswalk records: ", nrow(zip_to_puma))
message("ZIPs with both 2020 and 2010 PUMAs: ",
        sum(!is.na(zip_to_puma$PUMA_2020) & !is.na(zip_to_puma$PUMA_2010)))

# Preview the crosswalk
message("\nCrosswalk preview:")
print(head(zip_to_puma, 10))

########################################################################################
# STEP 4: Load and Process H-1B Data
########################################################################################

message("\n=== Step 4: Loading H-1B Petition Data ===\n")

# Load the H-1B data
h1b_data <- read_csv(input_file, show_col_types = FALSE)

message("Total H-1B records: ", nrow(h1b_data))

# Clean worksite ZIP codes
h1b_data <- h1b_data %>%
  mutate(
    # Clean the ZIP code for matching
    worksite_zip5 = clean_zip(petition_worksite_zip)
  )

# Check ZIP code cleaning results
message("Records with valid 5-digit worksite ZIP: ",
        sum(!is.na(h1b_data$worksite_zip5)))
message("Records with missing/invalid worksite ZIP: ",
        sum(is.na(h1b_data$worksite_zip5)))

########################################################################################
# STEP 5: Join PUMA Codes to H-1B Data
########################################################################################

message("\n=== Step 5: Joining PUMA Codes ===\n")

# Join the PUMA crosswalk to H-1B data
h1b_with_pumas <- h1b_data %>%
  left_join(
    zip_to_puma,
    by = c("worksite_zip5" = "ZIP5")
  )

# Summary statistics
message("\n--- PUMA Assignment Summary ---")
message("Total records: ", nrow(h1b_with_pumas))
message("Records with 2020 PUMA: ", sum(!is.na(h1b_with_pumas$PUMA_2020)))
message("Records with 2010 PUMA: ", sum(!is.na(h1b_with_pumas$PUMA_2010)))
message("Records missing 2020 PUMA: ", sum(is.na(h1b_with_pumas$PUMA_2020)))
message("Records missing 2010 PUMA: ", sum(is.na(h1b_with_pumas$PUMA_2010)))

# Calculate match rates
match_rate_2020 <- mean(!is.na(h1b_with_pumas$PUMA_2020)) * 100
match_rate_2010 <- mean(!is.na(h1b_with_pumas$PUMA_2010)) * 100
message("\n2020 PUMA match rate: ", round(match_rate_2020, 1), "%")
message("2010 PUMA match rate: ", round(match_rate_2010, 1), "%")

# Show unmatched ZIP codes (for diagnostics)
unmatched_zips <- h1b_with_pumas %>%
  filter(is.na(PUMA_2020), !is.na(worksite_zip5)) %>%
  count(worksite_zip5, sort = TRUE)

if (nrow(unmatched_zips) > 0) {
  message("\n--- Top 10 Unmatched ZIP Codes ---")
  print(head(unmatched_zips, 10))
}

########################################################################################
# STEP 6: Create State-PUMA Codes (Standard Format)
########################################################################################

message("\n=== Step 6: Creating State-PUMA Codes ===\n")

# PUMAs are unique only within states. The standard format is SSFFFFFF where:
# SS = 2-digit state FIPS code
# FFFFFF = PUMA code (padded)
# The GEOID from Census already includes state FIPS, so we need to parse it

# The GEOID_PUMA5_20 format is: 2-digit state FIPS + 5-digit PUMA code
# Example: "0100100" = Alabama (01) + PUMA 00100

h1b_with_pumas <- h1b_with_pumas %>%
  mutate(
    # Extract state FIPS from PUMA codes
    state_fips_2020 = str_sub(PUMA_2020, 1, 2),
    state_fips_2010 = str_sub(PUMA_2010, 1, 2),

    # Extract PUMA-only code (without state)
    puma_code_2020 = str_sub(PUMA_2020, 3, 7),
    puma_code_2010 = str_sub(PUMA_2010, 3, 7)
  )

message("State-PUMA codes created")
message("Unique 2020 state-PUMA combinations: ", n_distinct(h1b_with_pumas$PUMA_2020, na.rm = TRUE))
message("Unique 2010 state-PUMA combinations: ", n_distinct(h1b_with_pumas$PUMA_2010, na.rm = TRUE))

########################################################################################
# STEP 7: Save Output
########################################################################################

message("\n=== Step 7: Saving Output ===\n")

# Select columns to keep (original columns + new PUMA columns)
# Remove the intermediate worksite_zip5 column used for matching

output_data <- h1b_with_pumas %>%
  select(
    -worksite_zip5  # Remove intermediate column
  )

# Save to CSV
write_csv(output_data, output_file)

message("Output saved to: ", output_file)
message("Output rows: ", nrow(output_data))
message("Output columns: ", ncol(output_data))

########################################################################################
# STEP 8: Final Summary
########################################################################################

message("\n")
message("=" %>% rep(70) %>% paste(collapse = ""))
message("                    GEOCODING COMPLETE")
message("=" %>% rep(70) %>% paste(collapse = ""))
message("\n")

# Summary table of new columns added
new_cols <- c("PUMA_2020", "PUMA_2020_NAME", "PUMA_2010", "PUMA_2010_NAME",
              "state_fips_2020", "state_fips_2010", "puma_code_2020", "puma_code_2010")

message("New columns added:")
for (col in new_cols) {
  non_na <- sum(!is.na(output_data[[col]]))
  message(sprintf("  %-20s: %d non-missing values (%.1f%%)",
                  col, non_na, non_na/nrow(output_data)*100))
}

message("\n")
message("Column descriptions:")
message("  PUMA_2020        : 7-digit 2020 PUMA code (state FIPS + PUMA)")
message("  PUMA_2020_NAME   : Descriptive name for 2020 PUMA")
message("  PUMA_2010        : 7-digit 2010 PUMA code (state FIPS + PUMA)")
message("  PUMA_2010_NAME   : Descriptive name for 2010 PUMA")
message("  state_fips_2020  : 2-digit state FIPS (from 2020 PUMA)")
message("  state_fips_2010  : 2-digit state FIPS (from 2010 PUMA)")
message("  puma_code_2020   : 5-digit PUMA-only code (2020)")
message("  puma_code_2010   : 5-digit PUMA-only code (2010)")

message("\n")
message("To link to ACS PUMS data:")
message("  - For 2022+ ACS: Use PUMA_2020 (or state_fips_2020 + puma_code_2020)")
message("  - For 2012-2021 ACS: Use PUMA_2010 (or state_fips_2010 + puma_code_2010)")
message("\n")
