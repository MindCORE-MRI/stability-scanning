## Script to read in stability metrics and generate some reports

#install.packages(c("ggplot2", "readr", "fs", "dplyr", "tidyr", "RColorBrewer", "lubridate"), repos = "https://cloud.r-project.org")

# Load packages
library(ggplot2)
library(readr)
library(fs)
library(dplyr)
library(tidyr)
#library(colorspace)
#library(viridisLite)
library(RColorBrewer)
library(lubridate)


# Set working directory as the home directory on the data transfer computer
setwd("~/stability")

# Define scan sequences. Names are hard-coded, so will need to be updated if anything changes on the scanner.
sequences <- c(
  'ses64ch_funcbold_acqcmrrstd_taskwarmup',
  'ses64ch_funcbold_acqsiemensstd_tasktsnr',
  'ses64ch_funcbold_acqcmrrstd_tasktsnr',
  'ses64ch_funcbold_acqsiemensbasic_tasktsnr',
  'ses64ch_funcbold_acqcmrrstd_tasktsnrxacpc',
  'ses32ch_funcbold_acqsiemensstd_tasktsnr',
  'ses32ch_funcbold_acqsiemensbasic_tasktsnr',
  'ses32ch_funcbold_acqcmrrstd_tasktsnr',
  'ses32ch_funcbold_acqcmrrstd_tasktsnrxacpc',
  'ses20ch_funcbold_acqsiemensstd_tasktsnr',
  'ses20ch_funcbold_acqcmrrstd_tasktsnr',
  'ses20ch_funcbold_acqcmrrstd_tasktsnrxacpc'
)

sequence_descriptions <- c(
  'CMRR Warmup, 2mm^3',
  'Siemens Grappa=2, 3mm^3',
  'CMRR MB=3, 2mm^3',
  'Siemens Basic, 3mm^3',
  'CMRR MB=3, ACPC aligned, 2mm^3',
  'Siemens Grappa=2, 3mm^3',
  'Siemens Basic, 3mm^3',
  'CMRR MB=3, 2mm^3',
  'CMRR MB=3, ACPC aligned, 2mm^3',
  'Siemens Grappa=2, 3mm^3',
  'CMRR MB=3, 2mm^3',
  'CMRR MB=3, ACPC aligned, 2mm^3'
)

sequence_labels <- setNames(sequence_descriptions, sequences)

# Create output directory. "dir_create" silently ignores existing directories.
dir_create("Graphs")

# Find scan date folders
scan_dirs <- dir_ls(glob = "Stability_*", type = "directory")
scan_dates <- gsub("Stability_", "", basename(scan_dirs))
scan_dates <- as.Date(scan_dates, format = "%Y%m%d")

# Initialize storage
n_seq <- length(sequences)
n_days <- length(scan_dirs)
metrics <- list(SNR = matrix(NA_real_, n_seq, n_days),
                SFNR = matrix(NA_real_, n_seq, n_days),
                MeanGhost = matrix(NA_real_, n_seq, n_days))

# Loop over sequences and scan dates
for (i in seq_along(sequences)) {
  for (j in seq_along(scan_dirs)) {
    
    dirs <- list.dirs(scan_dirs[j], full.names = TRUE, recursive = TRUE)
    matching_dir <- dirs[grepl(sequences[i], dirs)]
    
    if (length(matching_dir) > 0) {
      folder <- matching_dir[1]
      snr_file <- file.path(folder, "snr.txt")
      sfnr_file <- file.path(folder, "sfnr.txt")
      ghost_file <- file.path(folder, "meanGhost.txt")
      
      # Read snr.txt
      if (file_exists(snr_file) && file_info(snr_file)$size > 1) {
        metrics$SNR[i, j] <- tryCatch(
          read_lines(snr_file) %>% as.numeric(),
          error = function(e) NA_real_
        )
      }
      
      # Read sfnr.txt
      if (file_exists(sfnr_file) && file_info(sfnr_file)$size > 1) {
        metrics$SFNR[i, j] <- tryCatch(
          read_lines(sfnr_file) %>% as.numeric(),
          error = function(e) NA_real_
        )
      }
      
      # Read meanGhost.txt
      if (file_exists(ghost_file) && file_info(ghost_file)$size > 1) {
        metrics$MeanGhost[i, j] <- tryCatch(
          read_lines(ghost_file) %>% as.numeric(),
          error = function(e) NA_real_
        )
      }
    }
  }
}


# Reshape data for plotting
metric_data <- bind_rows(
  lapply(names(metrics), function(metric) {
    expand.grid(
      Sequence = sequences,
      Date = scan_dates,
      Metric = metric
    ) %>% 
      mutate(Value = as.vector(metrics[[metric]]))
  })
)

metric_data <- metric_data %>%
  mutate(
    HeadCoil = case_when(
      grepl("ses64ch", Sequence) ~ "64-Ch",
      grepl("ses32ch", Sequence) ~ "32-Ch",
      grepl("ses20ch", Sequence) ~ "20-Ch"
    ),
    Metric = factor(Metric, levels = c("SNR", "SFNR", "MeanGhost")),
    Date = as.Date(Date)
  )

### Plot ### 

# List of head coils
head_coils <- unique(metric_data$HeadCoil)

# Create named color vector
unique_sequences <- unique(metric_data$Sequence)
n_colors <- length(unique_sequences)
#colors <- scales::hue_pal()(n_colors)  # auto-generate N colors
#colors <- qualitative_hcl(n_colors, palette = "Set 2")
#colors <- viridis(n_colors, option = "A", direction = -1)
colors <- brewer.pal(n_colors, "Set3")

sequence_labels <- setNames(sequence_descriptions, sequences)
color_values <- setNames(colors, sequences)

# Loop over each head coil to generate and save a figure
for (coil in unique(metric_data$HeadCoil)) {
  this_data <- metric_data %>% filter(HeadCoil == coil)
  
  p <- ggplot(this_data, aes(x = Date, y = Value, color = Sequence, group = Sequence)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 2) +
    facet_wrap(~ Metric, scales = "free_y", nrow = 1) +
    scale_y_continuous(limits = c(0, NA), expand = c(0, 0)) +  # Y axis starts at 0
    scale_x_date(date_breaks = "1 month", date_labels = "%b\n%Y") +  # Show months
    scale_color_manual(
      values = color_values,
      labels = sequence_labels
    ) +
    theme_minimal(base_size = 14) +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "bottom",
      legend.box = "vertical",
      legend.title = element_blank()
    ) +
    labs(
      title = paste(coil, "Coil Stability Measures"),
      x = "Scan Date",
      y = "Value"
    )

  ggsave(filename = paste0("Graphs/", coil, "_summary.png"), plot = p,
         width = 14, height = 5, dpi = 300)
}

#add another double loop to create separate plots for each metric

### Individual Metric Plots ###

# Get unique metrics
metrics <- unique(metric_data$Metric)

# Loop over coils
for (coil in unique(metric_data$HeadCoil)) {
  
  coil_data <- metric_data %>% filter(HeadCoil == coil)
  
  # Loop over metrics
  for (metric in metrics) {
    
    this_data <- coil_data %>% filter(Metric == metric)
    
    p <- ggplot(this_data, aes(x = Date, y = Value, color = Sequence, group = Sequence)) +
      geom_line(linewidth = 0.8) +
      geom_point(size = 2) +
      scale_y_continuous(limits = c(0, NA), expand = c(0, 0)) +
      scale_x_date(date_breaks = "1 month", date_labels = "%b\n%Y") +
      scale_color_manual(
        values = color_values,
        labels = sequence_labels
      ) +
      theme_minimal(base_size = 14) +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "bottom",
        legend.box = "vertical",
        legend.title = element_blank()
      ) +
      labs(
        title = paste(coil, "-", metric),
        x = "Scan Date",
        y = "Value"
      )
    
    ggsave(
      filename = paste0("Graphs/", coil, "_", gsub(" ", "_", metric), ".png"),
      plot = p,
      width = 7,
      height = 5,
      dpi = 300
    )
  }
}




## Gradient coil temps
df <- read_csv("GradientCoilTemps.csv") %>%
  mutate(Date = mdy(Date))

# Convert to long format
df_long <- df %>%
  pivot_longer(
    cols = -Date,
    names_to = "Measurement",
    values_to = "Temperature"
  ) %>%
  mutate(
    Measurement = factor(
      Measurement,
      levels = c(
        "GC4 Temp Start",
        "GC4 Temp Post-EPI1",
        "GC4 Temp Post-EPI2",
        "GC4 Temp Post-EPI3"
      )
    )
  )


# Create the plot
p <- ggplot(df_long, aes(x = Date, y = Temperature, color = Measurement)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2) +
  scale_x_date(date_breaks = "1 month", date_labels = "%b\n%Y") +  # Show months
  theme_minimal(base_size = 14) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    legend.position = "bottom",
    legend.box = "vertical",
    legend.title = element_blank()
    ) +
  labs(
    title = "Gradient Coil Temperatures",
    x = "Scan Date",
    y = "Temperature (°C)",
    color = "Measurement"
  )

# Save as PNG
ggsave(
  filename = "Graphs/gradient_coil_temps.png", plot = p,
  width = 14, height = 5, dpi = 300)


# HTML export
html_file <- "Summary.html"
cat('<!DOCTYPE html>
<html>
<head>
  <title>Stability Measures</title>
  <style>
    img { width: 100%; height: auto; }
  </style>
</head>
<body>
  <h1>Scanner Stability Measures</h1>
  <img src="Graphs/64-Ch_summary.png" alt="64-channel head coil summary">
  <img src="Graphs/32-Ch_summary.png" alt="32-channel head coil summary">
  <img src="Graphs/20-Ch_summary.png" alt="20-channel head coil summary">
  <img src="Graphs/gradient_coil_temps.png" alt="Gradient coil temps">
</body>
</html>', file = html_file)

cat(sprintf('HTML file "%s" created successfully.\n', html_file))
