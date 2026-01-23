# ============================================================================
# Pipeline Debugging Script
# ============================================================================
# Run this to diagnose issues before running the full pipeline
# ============================================================================

cat("\n=== H-1B Pipeline Diagnostics ===\n\n")

# 1. Check R version
cat("1. R Version Check:\n")
cat("   Current version:", as.character(getRversion()), "\n")
if (getRversion() < "4.0.0") {
  cat("   ⚠️  WARNING: R version should be 4.0.0 or higher\n")
} else {
  cat("   ✓ R version OK\n")
}

# 2. Check memory
cat("\n2. Memory Check:\n")
mem_info <- memory.size(max = NA)  # Windows only
if (is.na(mem_info)) {
  # Mac/Linux - use different method
  cat("   Available memory: Use Activity Monitor (Mac) or top (Linux) to check\n")
  cat("   Recommendation: At least 16GB RAM for this analysis\n")
} else {
  cat("   Memory limit:", mem_info, "MB\n")
}

# 3. Check working directory
cat("\n3. Working Directory:\n")
cat("   Current:", getwd(), "\n")
expected <- "~/Documents/GitHub/h1b_analysis_pipeline"
expected_full <- path.expand(expected)
if (normalizePath(getwd()) == normalizePath(expected_full)) {
  cat("   ✓ Correct directory\n")
} else {
  cat("   ⚠️  Expected:", expected_full, "\n")
  cat("   Run: setwd('", expected_full, "')\n", sep = "")
}

# 4. Check config.R loads
cat("\n4. Configuration Check:\n")
tryCatch({
  source("config.R")
  cat("   ✓ config.R loaded successfully\n")
  cat("   Data path:", data_raw, "\n")
}, error = function(e) {
  cat("   ✗ ERROR loading config.R:", conditionMessage(e), "\n")
})

# 5. Check packages
cat("\n5. Package Check:\n")
required_packages <- c("readxl", "dplyr", "tidyr", "stringr", "fuzzyjoin",
                      "purrr", "tidygeocoder", "sf", "tidycensus", "ipumsr",
                      "tidyverse", "scales", "matrixStats", "readr", "knitr")

for (pkg in required_packages) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    # Try to load it
    tryCatch({
      library(pkg, character.only = TRUE)
      cat("   ✓", pkg, "\n")
    }, error = function(e) {
      cat("   ✗", pkg, "- ERROR loading:", conditionMessage(e), "\n")
    })
  } else {
    cat("   ✗", pkg, "- NOT INSTALLED\n")
  }
}

# 6. Check for data files
cat("\n6. Data File Check:\n")
if (exists("data_raw")) {
  foia_files <- list.files(data_raw, pattern = "TRK_13139_FY.*\\.csv")
  if (length(foia_files) > 0) {
    cat("   ✓ Found", length(foia_files), "FOIA files\n")
  } else {
    cat("   ⚠️  No FOIA files found in", data_raw, "\n")
  }

  if (dir.exists(file.path(data_raw, "LCA_Data"))) {
    lca_files <- list.files(file.path(data_raw, "LCA_Data"), pattern = "\\.xlsx$")
    cat("   ✓ Found", length(lca_files), "LCA files\n")
  } else {
    cat("   ⚠️  LCA_Data directory not found\n")
  }

  acs_files <- list.files(data_raw, pattern = "usa_.*\\.(xml|dat\\.gz)$")
  if (length(acs_files) > 0) {
    cat("   ✓ Found", length(acs_files), "ACS files\n")
  } else {
    cat("   ⚠️  No ACS files found\n")
  }
}

# 7. Test reading a small data file
cat("\n7. File Reading Test:\n")
tryCatch({
  # Try to read first FOIA file
  if (exists("foia_files") && length(foia_files) > 0) {
    test_file <- file.path(data_raw, foia_files[1])
    cat("   Testing read of:", basename(test_file), "\n")
    test_data <- read.csv(test_file, nrows = 10)
    cat("   ✓ Successfully read", nrow(test_data), "rows,", ncol(test_data), "columns\n")
    rm(test_data)
  }
}, error = function(e) {
  cat("   ✗ ERROR reading file:", conditionMessage(e), "\n")
})

# 8. Memory stress test
cat("\n8. Memory Allocation Test:\n")
tryCatch({
  # Try to allocate a moderate-sized matrix
  test_matrix <- matrix(0, nrow = 10000, ncol = 1000)
  cat("   ✓ Can allocate 10,000 x 1,000 matrix (",
      format(object.size(test_matrix), units = "MB"), ")\n")
  rm(test_matrix)
  gc()  # Garbage collection
}, error = function(e) {
  cat("   ✗ Memory allocation failed:", conditionMessage(e), "\n")
  cat("   ⚠️  You may not have enough RAM for this analysis\n")
})

# 9. Check for common issues
cat("\n9. Common Issues Check:\n")

# Check if running in RStudio
if (Sys.getenv("RSTUDIO") == "1") {
  cat("   Running in RStudio\n")
  cat("   💡 If crashes persist, try running from terminal R instead\n")
  cat("      (RStudio can use more memory overhead)\n")
} else {
  cat("   Running in terminal R\n")
}

# Check if on Mac with Apple Silicon
if (Sys.info()["sysname"] == "Darwin" && Sys.info()["machine"] == "arm64") {
  cat("   ⚠️  Running on Apple Silicon (M1/M2/M3)\n")
  cat("   💡 Ensure R packages are compiled for arm64\n")
  cat("      Some spatial packages (sf, tigris) may need special setup\n")
}

cat("\n=== Diagnostic Complete ===\n\n")
cat("Common fixes for fatal errors:\n")
cat("1. Close other applications to free up RAM\n")
cat("2. Restart R session: Cmd+Shift+F10 (Mac) or Ctrl+Shift+F10 (Windows)\n")
cat("3. Update all packages: update.packages(ask = FALSE)\n")
cat("4. If using RStudio, increase memory limit in Tools > Global Options > General\n")
cat("5. Run scripts one at a time instead of full pipeline\n")
cat("6. Check for corrupted data files\n\n")
