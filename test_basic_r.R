# Test basic R functionality to isolate the issue

cat("Testing basic R functions...\n\n")

# Test 1: Can we get the current time?
cat("Test 1: Sys.time()\n")
tryCatch({
  cat("  Attempting Sys.time()...\n")
  flush.console()
  time1 <- Sys.time()
  cat("  ✓ Success:", as.character(time1), "\n")
}, error = function(e) {
  cat("  ✗ ERROR:", conditionMessage(e), "\n")
})

# Test 2: Can we get date?
cat("\nTest 2: Sys.Date()\n")
tryCatch({
  cat("  Attempting Sys.Date()...\n")
  flush.console()
  date1 <- Sys.Date()
  cat("  ✓ Success:", as.character(date1), "\n")
}, error = function(e) {
  cat("  ✗ ERROR:", conditionMessage(e), "\n")
})

# Test 3: Check timezone
cat("\nTest 3: System timezone\n")
tryCatch({
  tz <- Sys.timezone()
  cat("  Timezone:", tz, "\n")
}, error = function(e) {
  cat("  ✗ ERROR:", conditionMessage(e), "\n")
})

# Test 4: Check locale
cat("\nTest 4: System locale\n")
tryCatch({
  locale <- Sys.getlocale()
  cat("  Locale:", substr(locale, 1, 100), "...\n")
}, error = function(e) {
  cat("  ✗ ERROR:", conditionMessage(e), "\n")
})

# Test 5: Session info
cat("\nTest 5: R Session Info\n")
cat("  R version:", R.version.string, "\n")
cat("  Platform:", R.version$platform, "\n")
cat("  Running on:", Sys.info()["sysname"], Sys.info()["release"], "\n")

cat("\n=== Tests Complete ===\n")
