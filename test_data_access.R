# Test which data files can be accessed

cat("Testing data file access...\n\n")

# Load config
source("config.R")

# Test 1: Check working directory
cat("1. Working Directory:\n")
cat("   Current:", getwd(), "\n")
cat("   Expected:", project_root, "\n")
if (getwd() != project_root) {
  cat("   ⚠️  WARNING: Not in project root!\n")
  cat("   Run: setwd('", project_root, "')\n", sep = "")
}

# Test 2: Check data_raw path
cat("\n2. Data Raw Path:\n")
cat("   Path:", data_raw, "\n")
cat("   Exists:", dir.exists(data_raw), "\n")

# Test 3: FOIA files
cat("\n3. FOIA Files:\n")
foia_test <- list.files(data_raw, pattern = "TRK_13139_FY.*\\.csv", full.names = TRUE)
if (length(foia_test) > 0) {
  for (f in foia_test) {
    exists <- file.exists(f)
    readable <- file.access(f, mode = 4) == 0  # mode 4 = read permission
    cat("   ", basename(f), "- Exists:", exists, "Readable:", readable, "\n")
    if (exists && readable) {
      # Try to read first line
      tryCatch({
        test_read <- read.csv(f, nrows = 1)
        cat("      ✓ Can read file\n")
      }, error = function(e) {
        cat("      ✗ ERROR reading:", conditionMessage(e), "\n")
      })
    }
  }
} else {
  cat("   ✗ No FOIA files found!\n")
}

# Test 4: LCA Data directory
cat("\n4. LCA Data Directory:\n")
lca_dir <- file.path(data_raw, "LCA_Data")
cat("   Path:", lca_dir, "\n")
cat("   Exists:", dir.exists(lca_dir), "\n")
cat("   Is symlink:", Sys.readlink(lca_dir) != "", "\n")
if (Sys.readlink(lca_dir) != "") {
  cat("   Points to:", Sys.readlink(lca_dir), "\n")
}

if (dir.exists(lca_dir)) {
  lca_files <- list.files(lca_dir, pattern = "\\.xlsx$")
  cat("   Files found:", length(lca_files), "\n")
  if (length(lca_files) > 0) {
    # Test first file
    test_lca <- file.path(lca_dir, lca_files[1])
    cat("   Testing:", basename(test_lca), "\n")
    cat("      Exists:", file.exists(test_lca), "\n")
    cat("      Readable:", file.access(test_lca, mode = 4) == 0, "\n")
  }
} else {
  cat("   ✗ LCA_Data directory not found!\n")
}

# Test 5: Other required files
cat("\n5. Other Required Files:\n")
required_files <- c(
  "soc_2018_definitions.xlsx",
  "ZIP_COUNTY_122024.xlsx",
  "area_definitions_m2023.xlsx",
  "soc_2010_to_2018_crosswalk.xlsx",
  "DOT_to_ONET_SOC.xlsx"
)

for (fname in required_files) {
  fpath <- file.path(data_raw, fname)
  exists <- file.exists(fpath)
  if (exists) {
    readable <- file.access(fpath, mode = 4) == 0
    cat("   ✓", fname, "- Readable:", readable, "\n")
  } else {
    cat("   ✗", fname, "- NOT FOUND\n")
  }
}

# Test 6: OFLC wages
cat("\n6. OFLC Wages Directory:\n")
oflc_dir <- file.path(data_raw, "OFLC_Wages_2024-25")
cat("   Path:", oflc_dir, "\n")
cat("   Exists:", dir.exists(oflc_dir), "\n")
if (dir.exists(oflc_dir)) {
  oflc_files <- list.files(oflc_dir, pattern = "ALC_Export.*\\.csv")
  cat("   CSV files found:", length(oflc_files), "\n")
  if (length(oflc_files) > 0) {
    cat("   Files:", paste(oflc_files, collapse = ", "), "\n")
  }
}

# Test 7: ACS files
cat("\n7. ACS IPUMS Files:\n")
cat("   DDI file:", acs_ddi_file, "\n")
cat("   Exists:", file.exists(acs_ddi_file), "\n")
if (file.exists(acs_ddi_file)) {
  cat("   Readable:", file.access(acs_ddi_file, mode = 4) == 0, "\n")
}

acs_data <- gsub("\\.xml$", ".dat.gz", acs_ddi_file)
cat("   Data file:", acs_data, "\n")
cat("   Exists:", file.exists(acs_data), "\n")

cat("\n=== Test Complete ===\n")
cat("\nIf any files show 'Readable: FALSE', there's a permission issue.\n")
cat("If files don't exist, the symlinks may be broken.\n")
