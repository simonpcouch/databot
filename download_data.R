#!/usr/bin/env Rscript

# Create data directory if it doesn't exist
data_dir <- "data"
if (!dir.exists(data_dir)) {
  dir.create(data_dir)
}

# Define the data files to download
files <- c(
  "book.csv",
  "broadcast_media.csv",
  "journalism.csv",
  "leadership.csv",
  "restaurant_and_chef.csv"
)

# Base URL for the data
base_url <- "https://raw.githubusercontent.com/rfordatascience/tidytuesday/main/data/2024/2024-12-31"

# Download each file
for (file in files) {
  url <- file.path(base_url, file)
  dest <- file.path(data_dir, file)
  
  message("Downloading ", file, "...")
  download.file(url, dest, mode = "wb")
}
