# ==============================================================================
# Save All Control-Level Charts
# ==============================================================================
# This script adds explicit save commands for all key control-level charts
# Run this AFTER 03_wage_premium_analysis.R to save all individual charts
# ==============================================================================

# Assumes the analysis script has run and created all the chart data

library(ggplot2)
library(dplyr)
library(scales)

# Helper function
save_chart <- function(data, title, filename, type = "share") {
  if (type == "share") {
    p <- ggplot(data, aes(x = age_grp, y = share_positive)) +
      geom_col(width = 0.8, fill = ifp_colors$light_blue) +
      geom_text(aes(label = percent(share_positive, accuracy = 1)), vjust = -0.4, size = 3.5) +
      scale_y_continuous(labels = percent, limits = c(0, 1), expand = expansion(mult = c(0, 0.08))) +
      scale_x_discrete(labels = age_labels) +
      labs(
        title = title,
        x = "Age of H-1B recipient",
        y = "Share earning more than comparable natives"
      ) +
      theme_h1b()
  } else {
    p <- ggplot(data, aes(x = age_grp, y = avg_premium)) +
      geom_col(width = 0.8, fill = ifp_colors$light_blue) +
      geom_text(aes(
        label = paste0("$", round(avg_premium/1000), "k"),
        vjust = ifelse(avg_premium >= 0, -0.35, 1.15)
      ), size = 3) +
      scale_y_continuous(labels = dollar) +
      scale_x_discrete(labels = age_labels) +
      labs(
        title = title,
        x = "Age of H-1B recipient",
        y = "Average wage premium ($)"
      ) +
      theme_h1b()
  }

  ggsave(file.path(output_figures, filename), plot = p, width = 10, height = 6, dpi = 300)
  cat("  Saved:", filename, "\n")
}

cat("\n=== Saving All Control-Level Charts ===\n\n")

# Age Only
cat("Age Only Controls:\n")
save_chart(premium_age_only, "Share Positive Premium - Age Only", "01_share_positive_age_only.png", "share")
save_chart(avg_age_only, "Average Premium - Age Only", "02_avg_premium_age_only.png", "avg")

# Age + Education
cat("\nAge + Education Controls:\n")
save_chart(premium_ed_age, "Share Positive Premium - Age + Education", "03_share_positive_age_education.png", "share")
save_chart(avg_ed_age, "Average Premium - Age + Education", "04_avg_premium_age_education.png", "avg")

# Age + Occupation
cat("\nAge + Occupation Controls:\n")
save_chart(premium_occ_age, "Share Positive Premium - Age + Occupation", "05_share_positive_age_occupation.png", "share")
save_chart(avg_occ_age, "Average Premium - Age + Occupation", "06_avg_premium_age_occupation.png", "avg")

# Full Controls
cat("\nFull Controls (Age + Occ + Ed):\n")
save_chart(premium_full, "Share Positive Premium - Full Controls", "07_share_positive_full_controls.png", "share")
save_chart(avg_full, "Average Premium - Full Controls", "08_avg_premium_full_controls.png", "avg")

# Full + PUMA
cat("\nFull + PUMA Controls:\n")
save_chart(premium_puma, "Share Positive Premium - Full + PUMA", "09_share_positive_full_puma.png", "share")
save_chart(avg_puma, "Average Premium - Full + PUMA", "10_avg_premium_full_puma.png", "avg")

cat("\n✓ All control-level charts saved to:", output_figures, "\n\n")
