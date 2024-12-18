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
  on.exit(unlink(tmp_dir, recursive = TRUE))
  
  # Set up graphics device
  png_file <- file.path(tmp_dir, "Rplot%03d.png")
  dev_num <- dev.cur()
  png(png_file, width = 800, height = 600)
  dev.control("enable")
  
  # Evaluate the code and capture all outputs
  outputs <- evaluate::evaluate(
    code,
    envir = globalenv(), # evaluate in the global environment
    stop_on_error = 1, # stop on first error
    log_echo = TRUE,
    log_warning = FALSE
  )
  
  # Close the graphics device
  dev.off()
  
  # Process the outputs into a structured format
  result <- list(
    timestamp = "2024-12-10T11:31:12-08:00",
    outputs = list()
  )
  
  for (output in outputs) {
    str(output)
    entry <- list(type = class(output)[1])
    
    if (inherits(output, "source")) {
      entry$content <- as.character(output)
      entry$type <- "source"
    } else if (inherits(output, "warning")) {
      entry$content <- conditionMessage(output)
      entry$type <- "warning"
    } else if (inherits(output, "message")) {
      entry$content <- conditionMessage(output)
      entry$type <- "message"
    } else if (inherits(output, "error")) {
      entry$content <- conditionMessage(output)
      entry$type <- "error"
    } else if (inherits(output, "character")) {
      entry$content <- output
      entry$type <- "character"
    } else if (inherits(output, "value")) {
      entry$content <- utils::capture.output(print(output))
      entry$type <- "value"
    } else if (inherits(output, "recordedplot")) {
      # Save the plot to a PNG file
      plot_file <- tempfile(tmpdir = tmp_dir, fileext = ".png")
      png(plot_file, width = 640, height = 480)
      replayPlot(output)
      dev.off()
      
      # Convert the plot to base64
      plot_data <- base64enc::base64encode(plot_file)
      entry$content <- plot_data
      entry$mime <- "image/png"
      entry$type <- "recordedplot"
    }
    
    result$outputs[[length(result$outputs) + 1]] <- entry
  }
  
  result
}

output_to_elmer_content <- function(result) {
  contents <- lapply(result$outputs, function(output) {
    switch(output$type,
      source = NULL,
      error = paste0("**Error:** ", paste(output$content, collapse = "\n")),
      warning = paste0("**Warning:** ", paste(output$content, collapse = "\n")),
      message = paste(output$content, collapse = "\n"),
      character = paste(output$content, collapse = "\n"),
      value = paste(output$content, collapse = "\n"),
      recordedplot = elmer::ContentImageInline(
        type = output$mime,
        data = output$content
      ),
      {
        print(class(output))
        message("Ignoring output type: ", output$type)
      }
    )
  })

  coalesced <- Reduce(function(accum, elem) {
    if (is.null(elem)) {
      accum
    } else if (is.character(elem) && length(accum) > 0 && is.character(accum[length(accum)])) {
      accum[length(accum)] <- paste0(
        c(accum[length(accum)], elem),
        collapse = "\n"
      )
    } else {
      c(accum, list(elem))
    }
  }, contents, list())

  lapply(coalesced, function(content) {
    if (is.character(content)) {
      elmer::ContentText(content)
    } else {
      content
    }
  })
}