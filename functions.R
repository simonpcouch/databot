describe_vars <- function(varnames) {
  capture.output({
    for (i in varnames) {
      cat("Variable name: ", i, "\n", sep = "")
      cat("str(", i, "):\n", sep = "")
      rlang::inject(str(!!get(i, globalenv())))
      cat("\n")
    }
  })
}

#' Evaluate R code and capture all outputs in a structured format
#' @param code Character string containing R code to evaluate
#' @return List containing structured output information
evaluate_r_code <- function(code) {
  # Create a temporary directory for plots
  tmp_dir <- tempfile("reval")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE, after = FALSE)
  
  # Set up graphics device
  png_file <- file.path(tmp_dir, "Rplot%03d.png")
  png(png_file, width = 640, height = 480)
  dev.control("enable")
  dev_num <- dev.cur()
  on.exit(dev.off(dev_num), add = TRUE, after = FALSE)
  
  # Evaluate the code and capture all outputs
  outputs <- evaluate::evaluate(
    code,
    envir = globalenv(), # evaluate in the global environment
    stop_on_error = 1, # stop on first error
    log_echo = TRUE,
    log_warning = FALSE,
    output_handler = evaluate::new_output_handler(
      value = function(value, visible, lookup_env) {
        if (visible) {
          # Mostly to get ggplot2 to plot
          # Find the appropriate S3 method for `print` using class(value)
          capture.output(print(value))
          value
        } else {
          invisible(value)
        }
      }
    )
  )
  
  # Close the graphics device
  dev.off()
  
  # Process the outputs into a structured format
  result <- list(
    timestamp = "2024-12-10T11:31:12-08:00",
    outputs = list()
  )
  
  for (output in outputs) {
    entry <- list(type = class(output)[[1]])
    
    if (inherits(output, "source")) {
      entry$type <- "source"
      entry$content <- as.character(output)
    } else if (inherits(output, "warning")) {
      entry$type <- "warning"
      entry$content <- conditionMessage(output)
    } else if (inherits(output, "message")) {
      entry$type <- "message"
      entry$content <- conditionMessage(output)
    } else if (inherits(output, "error")) {
      entry$type <- "error"
      entry$content <- conditionMessage(output)
    } else if (inherits(output, "character")) {
      entry$type <- "text"
      entry$content <- output
    } else if (inherits(output, "recordedplot")) {
      entry$type <- "recordedplot"

      # Save the plot to a PNG file
      plot_file <- tempfile(tmpdir = tmp_dir, fileext = ".png")
      png(plot_file, width = 640, height = 480)
      tryCatch(
        {
          replayPlot(output)
        },
        finally = {
          dev.off()
        }
      )
      
      # Convert the plot to base64
      plot_data <- base64enc::base64encode(plot_file)
      entry$content <- plot_data
      entry$mime <- "image/png"
    } else {
      entry$type <- "value"
      entry$content <- utils::capture.output(print(output))
      entry$value <- output
    }
    
    result$outputs[[length(result$outputs) + 1]] <- entry
  }
  
  result
}

encode_df_for_model <- function(df, max_rows = 100, show_end = 10) {
  if (nrow(df) == 0) {
    return(paste(collapse = "\n", capture.output(print(tibble::as.tibble(df)))))
  }
  if (nrow(df) <= max_rows) {
    return(df_to_json(df))
  }
  head_rows <- df[1:max_rows, ]
  tail_rows <- df[(nrow(df) - show_end + 1):nrow(df), ]
  paste(collapse = "\n", c(
    df_to_json(head_rows),
    sprintf("... %d rows omitted ...", nrow(df) - max_rows),
    df_to_json(tail_rows))
  )
}

df_to_json <- function(df) {
  jsonlite::toJSON(df, dataframe = "rows", na = "string")
}
