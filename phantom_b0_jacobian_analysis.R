#!/usr/bin/env Rscript

library(tidyr)
library(ggplot2)

args <- commandArgs(trailingOnly = TRUE)

stats <- read.csv(args[1], header = TRUE)

# Create a long-form data frame
data_long <- pivot_longer(stats, cols = starts_with("LogJacobian"), names_to = "Jacobian", values_to = "Value")

# Assuming 'data_long' is already created and available
# Generate the plot
plot <- ggplot(data_long, aes(x = Slice, y = Value, color = Jacobian)) +
    geom_line() +
    labs(title = "Log Jacobian Values by Slice",
         x = "Slice",
         y = "Log Jacobian Value",
         color = "Jacobian Type") +
    theme_minimal()

# Save the plot to a PDF file
ggsave(args[2], plot, device = "pdf", width = 10, height = 6)

# Generate a summary score of how bad distortions are
ref_distortion <- median(data_long$Value[data_long$Jacobian == 'LogJacobian1'])
eddy_distortion <- median(data_long$Value[data_long$Jacobian != 'LogJacobian1'])

# Print the summary score
qc_score <-  eddy_distortion / ref_distortion

# write qc_score to a file by itself
cat(qc_score, file = args[3], sep = "")