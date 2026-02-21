# ==============================================================================
# STEP 2: Process FOIA Data (H-1B Petition Data)
# ==============================================================================
# What this does:
#   - Loads FOIA petition data (FY 2021-2024)
#   - Combines single and multi-registration files
#   - Renames variables for clarity
#   - Filters for lottery winners who filed petitions
#   - Saves checkpoint file
#
# Input:  data/raw/FOIA Data/TRK_13139_FY*.csv files
# Output: data/intermediate/step2_foia_processed.RData
# Time:   ~2 minutes
# Memory: ~1 GB
# ==============================================================================

cat("\n")
cat("======================================================================\n")
cat("  STEP 2: PROCESSING FOIA PETITION DATA\n")
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
checkpoint_file <- file.path(data_intermediate, "step2_foia_processed.RData")

# Check if already completed
if (file.exists(checkpoint_file)) {
  cat("✓ Step 2 already completed (checkpoint file exists)\n")
  cat("  File:", checkpoint_file, "\n")
  cat("  To re-run this step, delete the checkpoint file:\n")
  cat("    file.remove('", checkpoint_file, "')\n\n", sep="")
  cat("Loading existing data...\n")
  load(checkpoint_file)
  cat("✓ Loaded", nrow(foia_data), "FOIA petition records\n\n")
  quit(save = "no")
}

# Load required libraries
cat("Loading libraries...\n")
library(dplyr)
library(readr)

cat("✓ Libraries loaded\n\n")

# ==============================================================================
# Load and Combine FOIA Files
# ==============================================================================

cat("--- Loading FOIA Files ---\n")

# Save starting directory
original_dir <- getwd()

# Change to FOIA data directory
setwd(foia_data_path)

# List of files to load
foia_files_list <- c(
  "TRK_13139_FY2021.csv",
  "TRK_13139_FY2022.csv",
  "TRK_13139_FY2023.csv",
  "TRK_13139_FY2024_single_reg.csv",
  "TRK_13139_FY2024_multi_reg.csv"
)

# Read each file
foia_list <- list()

for (i in seq_along(foia_files_list)) {
  file_name <- foia_files_list[i]

  cat(sprintf("[%d/%d] Reading %s... ", i, length(foia_files_list), file_name))

  if (!file.exists(file_name)) {
    cat("ERROR: File not found!\n")
    stop("Missing FOIA file: ", file_name)
  }

  # Read CSV
  foia_file <- read.csv(file_name, stringsAsFactors = FALSE)

  foia_list[[i]] <- foia_file

  cat(sprintf("%s rows\n", format(nrow(foia_file), big.mark = ",")))

  rm(foia_file)
  gc(verbose = FALSE)
}

cat("\nCombining FOIA files...\n")
foia_combined <- bind_rows(foia_list)
rm(foia_list)
gc(verbose = FALSE)

cat(sprintf("Total records: %s\n\n", format(nrow(foia_combined), big.mark = ",")))

# ==============================================================================
# Rename Variables for Clarity
# ==============================================================================

cat("--- Renaming Variables ---\n")

foia_data <- foia_combined %>%
  rename(
    registration_id = bcn,
    registration_birth_country = country_of_birth,
    registration_nationality = country_of_nationality,
    registration_dob = ben_date_of_birth,
    registration_birth_year = ben_year_of_birth,
    registration_gender = gender,
    registration_employer_name = employer_name,
    registration_FEIN = FEIN,
    registration_empl_addr = mail_addr,
    registration_empl_city = city,
    registration_empl_state = state,
    registration_empl_zip = zip,
    registration_agent_first = agent_first_name,
    registration_agent_last = agent_last_name,
    registration_lottery_year = lottery_year,
    registration_status = status_type,
    registration_duplicate = ben_multi_reg_ind,
    petition_id = RECEIPT_NUMBER,
    petition_recieve_date = rec_date,
    petition_decision = FIRST_DECISION,
    petition_decision_date = first_decision_date,
    petition_employer_name = i129_employer_name,
    petition_empl_addr = PET_STREET,
    petition_empl_city = PET_CITY,
    petition_empl_state = PET_STATE,
    petition_empl_zip = PET_ZIP,
    petition_request_class = REQUESTED_CLASS,
    petition_classificiation_basis = BASIS_FOR_CLASSIFICATION,
    petition_request_action = REQUESTED_ACTION,
    petition_beneficiary_num = NUMBER_OF_BENEFICIARIES,
    petition_beneficiary_gender = BEN_SEX,
    petition_beneficiary_birth_country = BEN_COUNTRY_OF_BIRTH,
    petition_beneficiary_classif = BEN_CURRENT_CLASS,
    petition_beneficiary_dot_title = JOB_TITLE,
    petition_worksite_addr = WORKSITE_STREET,
    petition_worksite_city = WORKSITE_CITY,
    petition_worksite_state = WORKSITE_STATE,
    petition_worksite_zip = WORKSITE_ZIP,
    petition_beneficiary_full_time = FULL_TIME_IND,
    petition_beneficiary_wage = WAGE_AMT,
    petition_beneficiary_wage_unit = WAGE_UNIT,
    petition_classif_valid_start_date = valid_from,
    petition_classif_valid_end_date = valid_to,
    petition_n_employees = NUM_OF_EMP_IN_US,
    petition_employer_h1b_dependent = S1Q1A,
    petition_wilful_violator = S1Q1B,
    petition_beneficiary_edu_code = BEN_EDUCATION_CODE,
    petition_beneficiary_edu_defin = ED_LEVEL_DEFINITION,
    petition_beneficiary_field = BEN_PFIELD_OF_STUDY,
    petition_annual_pay = BEN_COMP_PAID,
    petition_beneficiary_dot_occ_code = DOT_CODE,
    petition_employer_naics = NAICS_CODE,
    petition_h1b_type = S3Q1,
    petition_beneficiary_off_site_work = S4Q1,
    petition_beneficiary_protected_population = T_U_VAWA_FLAG
  ) %>%
  relocate(registration_lottery_year)

cat("✓ Variables renamed\n\n")

# Clean up
rm(foia_combined)
gc(verbose = FALSE)

# ==============================================================================
# Filter and Clean
# ==============================================================================

cat("--- Filtering and Cleaning Data ---\n")

rows_before <- nrow(foia_data)

# Remove duplicates
foia_data <- foia_data %>% distinct()
rows_after_dedup <- nrow(foia_data)
cat(sprintf("Removed duplicates: %s → %s records\n",
            format(rows_before, big.mark = ","),
            format(rows_after_dedup, big.mark = ",")))

# Remove records censored under FOIA (privacy protection)
foia_data <- foia_data %>%
  filter(registration_birth_country != "(b)(3) (b)(6) (b)(7)(c)")
rows_after_filter <- nrow(foia_data)
cat(sprintf("Removed censored records: %s → %s records\n",
            format(rows_after_dedup, big.mark = ","),
            format(rows_after_filter, big.mark = ",")))

cat(sprintf("\nTotal cleaned records: %s (%.1f%% of original)\n",
            format(rows_after_filter, big.mark = ","),
            (rows_after_filter / rows_before) * 100))

# ==============================================================================
# SAVE CHECKPOINT
# ==============================================================================

cat("\n--- Saving Checkpoint ---\n")

# Return to original directory
setwd(original_dir)

save(foia_data, file = checkpoint_file)

cat("✓ Checkpoint saved:", checkpoint_file, "\n")
cat(sprintf("  File size: %.1f MB\n", file.info(checkpoint_file)$size / 1024 / 1024))
cat(sprintf("  Records: %s\n", format(nrow(foia_data), big.mark = ",")))

# Memory cleanup
gc(verbose = FALSE)

cat("\n")
cat("======================================================================\n")
cat("  STEP 2 COMPLETE\n")
cat("======================================================================\n")
cat("\nNext step: source('scripts/simple/step3_merge_data.R')\n\n")
