# ==============================================================================
# Combine All Charts into Single PDF
# ==============================================================================
# This script combines all saved PNG charts into a single multi-page PDF
# ==============================================================================

library(png)
library(grid)

# Load config
source("config.R")

cat("\n=== Combining Charts into PDF ===\n\n")

# Get all chart files (numbered charts only, in order)
chart_files <- list.files(output_figures, pattern = "^[0-9]+_.*\\.png$", full.names = TRUE)
chart_files <- sort(chart_files)  # Sort by number

# Also get the comparison chart
comparison_file <- file.path(output_figures, "comparison_all_controls.png")
if (file.exists(comparison_file)) {
  chart_files <- c(chart_files, comparison_file)
}

cat("Found", length(chart_files), "charts to combine\n\n")

if (length(chart_files) == 0) {
  stop("No charts found in ", output_figures, "\n",
       "Please run the analysis script first: source('scripts/03_wage_premium_analysis.R')")
}

# Create PDF
pdf_file <- file.path(output_figures, "all_charts_combined.pdf")

# Open PDF device (letter size, landscape for better chart viewing)
pdf(pdf_file, width = 11, height = 8.5)

# Add each chart as a page
for (i in seq_along(chart_files)) {
  chart_file <- chart_files[i]
  chart_name <- basename(chart_file)

  cat("Adding chart", i, "of", length(chart_files), ":", chart_name, "\n")

  # Read PNG
  img <- readPNG(chart_file)

  # Create a new page
  grid.newpage()

  # Draw the image
  grid.raster(img)
}

# Close PDF device
dev.off()

cat("\n✓ PDF created successfully!\n")
cat("  Location:", pdf_file, "\n")
cat("  Pages:", length(chart_files), "\n\n")

# Open the PDF (Mac only)
if (Sys.info()["sysname"] == "Darwin") {
  cat("Opening PDF...\n")
  system(paste0("open '", pdf_file, "'"))
}
