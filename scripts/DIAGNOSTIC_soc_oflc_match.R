# =============================================================================
# DIAGNOSTIC: Check SOC code matching between H-1B data and OFLC tables
# =============================================================================

# Load configuration
if (file.exists("config.R")) {
  source("config.R")
} else if (file.exists("../config.R")) {
  source("../config.R")
} else {
  stop("Cannot find config.R")
}

library(dplyr)

cat("\n=============================================================================\n")
cat("DIAGNOSTIC: SOC Code Matching Issue\n")
cat("=============================================================================\n\n")

# Load H-1B data
h1b <- read.csv(file.path(data_processed, "h1b_with_mincer_wages.csv"))

# Check if Script 04 objects are in memory
if (!exists("oflc_bases") || !exists("occ_area_models")) {
  cat("Model objects not in memory. Loading Script 04...\n\n")
  source(file.path("scripts", "04 Calculate new prevailing wages.R"), local = FALSE)
}

# =============================================================================
# Compare SOC codes between H-1B and OFLC
# =============================================================================

cat("Checking SOC code format and availability...\n\n")

# Get unique SOC codes from H-1B data (with all required fields)
h1b_socs <- h1b %>%
  filter(!is.na(SOC_CODE),
         !is.na(MSA_code),
         !is.na(petition_beneficiary_edu_code),
         !is.na(registration_birth_year)) %>%
  distinct(SOC_CODE, SOC_TITLE) %>%
  arrange(SOC_CODE)

cat("Unique SOC codes in H-1B data (with all required fields):", nrow(h1b_socs), "\n")

# Get unique SOC codes from OFLC tables
oflc_socs_2022 <- oflc_bases[["ALC"]][["2022"]] %>%
  distinct(SocCode) %>%
  arrange(SocCode)

oflc_socs_2023 <- oflc_bases[["ALC"]][["2023"]] %>%
  distinct(SocCode) %>%
  arrange(SocCode)

cat("Unique SOC codes in OFLC 2022:", nrow(oflc_socs_2022), "\n")
cat("Unique SOC codes in OFLC 2023:", nrow(oflc_socs_2023), "\n\n")

# Check for software developers specifically
cat("=============================================================================\n")
cat("INVESTIGATING: Software Developers (15-1252)\n")
cat("=============================================================================\n\n")

sw_dev_in_h1b <- h1b_socs %>% filter(SOC_CODE == "15-1252")
sw_dev_in_oflc_2022 <- oflc_socs_2022 %>% filter(SocCode == "15-1252")
sw_dev_in_oflc_2023 <- oflc_socs_2023 %>% filter(SocCode == "15-1252")

cat("15-1252 in H-1B data:  ", ifelse(nrow(sw_dev_in_h1b) > 0, "YES", "NO"), "\n")
cat("15-1252 in OFLC 2022:  ", ifelse(nrow(sw_dev_in_oflc_2022) > 0, "YES", "NO"), "\n")
cat("15-1252 in OFLC 2023:  ", ifelse(nrow(sw_dev_in_oflc_2023) > 0, "YES", "NO"), "\n\n")

# Check what software developer codes ARE in OFLC
cat("Software developer related codes in OFLC 2022:\n")
sw_codes_2022 <- oflc_bases[["ALC"]][["2022"]] %>%
  filter(grepl("15-125", SocCode)) %>%
  distinct(SocCode, Area, Level3) %>%
  filter(Area == "41860") %>%  # San Francisco as example
  select(SocCode, Level3) %>%
  arrange(SocCode)
print(sw_codes_2022, n = 20)

cat("\n")
cat("Software developer related codes in OFLC 2023:\n")
sw_codes_2023 <- oflc_bases[["ALC"]][["2023"]] %>%
  filter(grepl("15-125", SocCode)) %>%
  distinct(SocCode, Area, Level3) %>%
  filter(Area == "41860") %>%  # San Francisco as example
  select(SocCode, Level3) %>%
  arrange(SocCode)
print(sw_codes_2023, n = 20)

# =============================================================================
# Check ACS OCCSOC codes
# =============================================================================

cat("\n")
cat("=============================================================================\n")
cat("INVESTIGATING: ACS OCCSOC Mapping\n")
cat("=============================================================================\n\n")

# Check if crosswalk exists
crosswalk_file <- file.path(data_raw, "occupation_oflc_to_acs_crowsswalk.csv")
if (file.exists(crosswalk_file)) {
  crosswalk <- read.csv(crosswalk_file)

  sw_dev_xwalk <- crosswalk %>%
    filter(SocCode == "15-1252")

  cat("15-1252 mapping in crosswalk:\n")
  print(sw_dev_xwalk)

  cat("\n")
  cat("All software developer mappings in crosswalk:\n")
  sw_dev_all_xwalk <- crosswalk %>%
    filter(grepl("15-125", SocCode)) %>%
    select(SocCode, ACS_OCCSOC, Match_Level, Match_Level_Description)
  print(sw_dev_all_xwalk, n = 30)
}

# Check available Mincer models
cat("\n")
cat("=============================================================================\n")
cat("INVESTIGATING: Available Mincer Models\n")
cat("=============================================================================\n\n")

# Get list of occupations with models
modeled_occs <- unique(sapply(occ_area_models, function(m) m$OCCSOC))
cat("Number of occupations with Mincer models:", length(modeled_occs), "\n\n")

# Check if software developer occupation exists
sw_dev_acs <- gsub("-", "", "15-1252")  # Remove hyphen: "151252"
cat("ACS OCCSOC for software developers (no hyphen):", sw_dev_acs, "\n")
cat("Model exists for", sw_dev_acs, ":", sw_dev_acs %in% modeled_occs, "\n\n")

# Check what 15-125X occupations have models
cat("Software developer related ACS codes with Mincer models:\n")
sw_dev_models <- modeled_occs[grepl("^15125", modeled_occs)]
print(sw_dev_models)

cat("\n")
cat("=============================================================================\n")
cat("DIAGNOSIS SUMMARY\n")
cat("=============================================================================\n\n")

cat("If software developers (15-1252) show:\n")
cat("  - YES in H-1B data\n")
cat("  - NO in OFLC tables\n")
cat("  - NO in Mincer models\n\n")

cat("Then the issue is likely:\n")
cat("  1. SOC code format mismatch (hyphen/no hyphen)\n")
cat("  2. OFLC uses different code for software developers in newer years\n")
cat("  3. Crosswalk maps 15-1252 to wrong ACS code or no code\n\n")

cat("Check the output above to see which scenario applies.\n\n")
