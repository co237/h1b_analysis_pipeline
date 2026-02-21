# ==============================================================================
# STEP 1: Process LCA Data (Labor Condition Applications)
# ==============================================================================
# What this does:
#   - Loads LCA data from 2015-2024 (quarterly 2020-2024, annual 2015-2019)
#   - Filters for H-1B visas only
#   - Selects relevant columns (case number, SOC codes, wages, etc.)
#   - Removes duplicates
#   - Saves checkpoint file
#
# Input:  data/raw/LCA_Data/*.xlsx files
# Output: data/intermediate/step1_lca_processed.RData
# Time:   ~5 minutes
# Memory: ~2 GB
# ==============================================================================

cat("\n")
cat("======================================================================\n")
cat("  STEP 1: PROCESSING LCA DATA\n")
cat("======================================================================\n\n")

# Load configuration
if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
} else if (file.exists("../../config.R")) {
  source("../../config.R")
} else {
  stop("Cannot find config.R")
}

# Define checkpoint file
checkpoint_file <- file.path(data_intermediate, "step1_lca_processed.RData")

# Check if already completed
if (file.exists(checkpoint_file)) {
  cat("✓ Step 1 already completed (checkpoint file exists)\n")
  cat("  File:", checkpoint_file, "\n")
  cat("  To re-run this step, delete the checkpoint file:\n")
  cat("    file.remove('", checkpoint_file, "')\n\n", sep="")
  cat("Loading existing data...\n")
  load(checkpoint_file)
  cat("✓ Loaded", nrow(lca_data), "LCA records\n\n")
  quit(save = "no")
}

# Load required libraries
cat("Loading libraries...\n")
library(readxl)
library(dplyr)
library(tidyr)
library(stringr)

cat("✓ Libraries loaded\n\n")

# ==============================================================================
# PART A: Process Quarterly LCA Data (2020-2024)
# ==============================================================================

cat("--- Part A: Processing Quarterly LCA Data (2020-2024) ---\n")

lca_quarterly <- list()
total_quarters <- 5 * 4  # 5 years × 4 quarters

# Save starting directory
original_dir <- getwd()

# Change to LCA data directory
setwd(lca_data_path)

quarter_count <- 0

for (year in 2020:2024) {
  for (quarter in 1:4) {
    quarter_count <- quarter_count + 1

    file_name <- paste0("LCA_Disclosure_Data_FY", year, "_Q", quarter, ".xlsx")

    cat(sprintf("[%2d/%2d] Reading %s... ", quarter_count, total_quarters, file_name))

    if (!file.exists(file_name)) {
      cat("SKIPPED (file not found)\n")
      next
    }

    # Read and process the file
    quarter_data <- read_xlsx(file_name, guess_max = 10000) %>%
      filter(VISA_CLASS == "H-1B") %>%  # H-1Bs only
      select(
        CASE_NUMBER,
        CASE_STATUS,
        VISA_CLASS,
        DECISION_DATE,
        PW_WAGE_LEVEL,
        SOC_CODE,
        SOC_TITLE,
        WORKSITE_COUNTY,
        WORKSITE_STATE,
        WAGE_RATE_OF_PAY_FROM,
        WAGE_RATE_OF_PAY_TO,
        PREVAILING_WAGE,
        WAGE_UNIT_OF_PAY
      ) %>%
      # Clean monetary columns (remove $ and commas)
      mutate(across(
        c(WAGE_RATE_OF_PAY_FROM, WAGE_RATE_OF_PAY_TO, PREVAILING_WAGE),
        ~ as.numeric(str_replace_all(., c("\\$" = "", "," = "")))
      )) %>%
      mutate(FISCAL_YEAR = year)

    # Store with unique ID
    quarter_id <- paste0(year, "_Q", quarter)
    lca_quarterly[[quarter_id]] <- quarter_data

    cat(sprintf("%s rows\n", format(nrow(quarter_data), big.mark = ",")))

    # Clean up memory
    rm(quarter_data)
    if (quarter_count %% 4 == 0) {
      gc(verbose = FALSE)
    }
  }
}

cat("\nCombining quarterly data...\n")
lca_2020_2024 <- bind_rows(lca_quarterly)
rm(lca_quarterly)  # Free memory
gc(verbose = FALSE)

cat("Removing duplicates...\n")
rows_before <- nrow(lca_2020_2024)
lca_2020_2024 <- lca_2020_2024 %>% distinct()
rows_after <- nrow(lca_2020_2024)
cat(sprintf("  Removed %s duplicate rows\n", format(rows_before - rows_after, big.mark = ",")))

cat(sprintf("✓ Quarterly data processed: %s records\n\n", format(nrow(lca_2020_2024), big.mark = ",")))

# ==============================================================================
# PART B: Process Annual LCA Data (2015-2019)
# ==============================================================================

cat("--- Part B: Processing Annual LCA Data (2015-2019) ---\n")

lca_annual <- list()

for (year in 2015:2019) {
  file_name <- paste0("H-1B_Disclosure_Data_FY", year, ".xlsx")

  cat(sprintf("Reading %s... ", file_name))

  if (!file.exists(file_name)) {
    cat("SKIPPED (file not found)\n")
    next
  }

  # Different years have different column names
  if (year == 2019) {
    year_data <- read_xlsx(file_name, guess_max = 10000) %>%
      filter(VISA_CLASS == "H-1B") %>%
      select(
        CASE_NUMBER,
        CASE_STATUS,
        VISA_CLASS,
        DECISION_DATE,
        WORKSITE_COUNTY_1,
        PW_WAGE_LEVEL_1,
        WORKSITE_STATE_1,
        SOC_CODE,
        SOC_TITLE,
        WAGE_RATE_OF_PAY_FROM_1,
        WAGE_RATE_OF_PAY_TO_1,
        PREVAILING_WAGE_1,
        WAGE_UNIT_OF_PAY_1
      ) %>%
      rename(
        WAGE_RATE_OF_PAY_FROM = WAGE_RATE_OF_PAY_FROM_1,
        WAGE_RATE_OF_PAY_TO = WAGE_RATE_OF_PAY_TO_1,
        PREVAILING_WAGE = PREVAILING_WAGE_1,
        PW_WAGE_LEVEL = PW_WAGE_LEVEL_1,
        WAGE_UNIT_OF_PAY = WAGE_UNIT_OF_PAY_1,
        WORKSITE_COUNTY = WORKSITE_COUNTY_1,
        WORKSITE_STATE = WORKSITE_STATE_1
      )
  } else if (year %in% 2016:2018) {
    year_data <- read_xlsx(file_name, guess_max = 10000) %>%
      filter(VISA_CLASS == "H-1B") %>%
      select(
        CASE_NUMBER,
        CASE_STATUS,
        VISA_CLASS,
        DECISION_DATE,
        SOC_CODE,
        SOC_NAME,
        WORKSITE_COUNTY,
        WORKSITE_STATE,
        WAGE_RATE_OF_PAY_FROM,
        WAGE_RATE_OF_PAY_TO,
        PREVAILING_WAGE,
        WAGE_UNIT_OF_PAY
      ) %>%
      rename(SOC_TITLE = SOC_NAME)
  } else {  # 2015
    year_data <- read_xlsx(file_name, guess_max = 10000) %>%
      filter(VISA_CLASS == "H-1B") %>%
      select(
        CASE_NUMBER,
        CASE_STATUS,
        CASE_SUBMITTED,
        SOC_CODE,
        SOC_NAME,
        WORKSITE_COUNTY,
        WORKSITE_STATE,
        WAGE_RATE_OF_PAY,
        PREVAILING_WAGE,
        WAGE_UNIT_OF_PAY,
        PW_WAGE_LEVEL
      ) %>%
      rename(
        DECISION_DATE = CASE_SUBMITTED,
        SOC_TITLE = SOC_NAME,
        WAGE_RATE_OF_PAY_FROM = WAGE_RATE_OF_PAY
      ) %>%
      mutate(
        VISA_CLASS = "H-1B",
        WAGE_RATE_OF_PAY_TO = NA_real_  # 2015 doesn't have "to" wage
      )
  }

  # Clean monetary columns and add fiscal year
  year_data <- year_data %>%
    mutate(across(
      c(WAGE_RATE_OF_PAY_FROM, WAGE_RATE_OF_PAY_TO, PREVAILING_WAGE),
      ~ as.numeric(str_replace_all(., c("\\$" = "", "," = "")))
    )) %>%
    mutate(FISCAL_YEAR = year)

  lca_annual[[as.character(year)]] <- year_data

  cat(sprintf("%s rows\n", format(nrow(year_data), big.mark = ",")))

  rm(year_data)
  gc(verbose = FALSE)
}

cat("\nCombining annual data...\n")
lca_2015_2019 <- bind_rows(lca_annual)
rm(lca_annual)
gc(verbose = FALSE)

cat(sprintf("✓ Annual data processed: %s records\n\n", format(nrow(lca_2015_2019), big.mark = ",")))

# ==============================================================================
# PART C: Combine All Years
# ==============================================================================

cat("--- Part C: Combining All LCA Data (2015-2024) ---\n")

lca_data <- bind_rows(lca_2020_2024, lca_2015_2019)
rm(lca_2020_2024, lca_2015_2019)
gc(verbose = FALSE)

cat(sprintf("Total records: %s\n", format(nrow(lca_data), big.mark = ",")))

# Final duplicate removal
rows_before <- nrow(lca_data)
lca_data <- lca_data %>% distinct()
rows_after <- nrow(lca_data)

if (rows_before != rows_after) {
  cat(sprintf("Removed %s more duplicates\n", format(rows_before - rows_after, big.mark = ",")))
}

# ==============================================================================
# SAVE CHECKPOINT
# ==============================================================================

cat("\n--- Saving Checkpoint ---\n")

# Return to original directory
setwd(original_dir)

save(lca_data, file = checkpoint_file)

cat("✓ Checkpoint saved:", checkpoint_file, "\n")
cat(sprintf("  File size: %.1f MB\n", file.info(checkpoint_file)$size / 1024 / 1024))
cat(sprintf("  Records: %s\n", format(nrow(lca_data), big.mark = ",")))

# Memory cleanup
gc(verbose = FALSE)

cat("\n")
cat("======================================================================\n")
cat("  STEP 1 COMPLETE\n")
cat("======================================================================\n")
cat("\nNext step: source('scripts/simple/step2_process_foia.R')\n\n")
