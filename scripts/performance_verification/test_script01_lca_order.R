# =============================================================================
# Verification test: script 01 nested for-loop → Map() + expand.grid()
# =============================================================================
#
# What changed:
#   The original code used a nested for-loop (outer: quarters 1–4,
#   inner: years 2020–2024) to read 20 quarterly LCA Excel files and
#   collect them in a named list. The new version defines a
#   read_lca_quarterly() helper and calls it via Map() over an
#   expand.grid() of all (year, quarter) pairs.
#
# The critical invariant is row order: bind_rows() on the resulting
# list must produce the same sequence as the original loop. This test
# mocks the file-reading step with a function that returns a marker
# row per (year, quarter) pair, then verifies that both approaches
# produce identical output sequences.
#
# Note: this test does not require any data files.
#
# Run from the project root:
#   Rscript scripts/performance_verification/test_script01_lca_order.R
# =============================================================================

# -----------------------------------------------------------------------------
# OLD: nested for-loop (verbatim structure from pre-change script 01)
# -----------------------------------------------------------------------------
old_result <- local({
  quarters <- list()
  for (i in 1:4) {
    for (year in 2020:2024) {
      id <- paste0(year, "_Q", i)
      # In the real script this is read_xlsx(...) — mocked here with a marker row
      quarters[[id]] <- data.frame(year = year, quarter = i, id = id,
                                   stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, quarters)
})

# -----------------------------------------------------------------------------
# NEW: expand.grid() + Map() (current script 01)
# -----------------------------------------------------------------------------
read_lca_quarterly <- function(year, quarter) {
  data.frame(year = year, quarter = quarter,
             id = paste0(year, "_Q", quarter),
             stringsAsFactors = FALSE)
}

lca_pairs     <- expand.grid(year = 2020:2024, quarter = 1:4, stringsAsFactors = FALSE)
quarters      <- Map(read_lca_quarterly, lca_pairs$year, lca_pairs$quarter)
new_result    <- do.call(rbind, quarters)

# -----------------------------------------------------------------------------
# Assert equivalence
# -----------------------------------------------------------------------------
cat("Old row order:", paste(old_result$id, collapse = "  "), "\n")
cat("New row order:", paste(new_result$id, collapse = "  "), "\n\n")

order_eq <- identical(old_result$id, new_result$id)
cat("Row order identical:", order_eq, "\n")

# Also verify against the explicitly-expected order derived from the original loop
expected_ids <- c()
for (i in 1:4) {
  for (year in 2020:2024) {
    expected_ids <- c(expected_ids, paste0(year, "_Q", i))
  }
}
cat("Matches hand-computed original loop order:", identical(new_result$id, expected_ids), "\n")

if (order_eq) {
  cat("\nRESULT: PASS\n")
} else {
  cat("\nExpected:", paste(expected_ids, collapse = "  "), "\n")
  stop("RESULT: FAIL — Map() produces different row order than original nested for-loop")
}
