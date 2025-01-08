#' @import shiny
#' @import bslib
#' @import ellmer
#' @import shinychat
NULL

html_deps <- function() {
  htmltools::htmlDependency(
    "databot",
    packageVersion("databot"),
    src = "www",
    package = "databot",
    script = "script.js",
    stylesheet = "style.css"
  )
}

#' Runs databot
#' 
#' @export
chat <- function() {
  withr::local_options(ellmer_verbosity = 2)
  withr::local_envvar(NO_COLOR = "1")

  default_turns <- NULL

  ui <- page_fillable(
    html_deps(),
    chat_ui("chat", fill = TRUE, height = "100%", width = "100%")
  )

  server <- function(input, output, session) {
    system_prompt_template <- paste(
      readLines(
        system.file("prompt/prompt.md", package = "databot"),
        encoding = "UTF-8",
        warn = FALSE
      ),
      collapse = "\n"
    )
    root_dir <- here::here()
    llms_txt <- NULL
    if (file.exists(here::here("llms.txt"))) {
      llms_txt <- paste(
        readLines(here::here("llms.txt"), encoding = "UTF-8", warn = FALSE),
        collapse = "\n"
      )
    }
    system_prompt <- whisker::whisker.render(system_prompt_template, data = list(
      has_project = TRUE, # TODO: Make this dynamic
      has_llms_txt = TRUE,
      llms_txt = llms_txt
    ))

    # Creates a Quarto report and displays it to the user
    #
    # @param filename The desired filename of the report. Should end in `.qmd`.
    # @param content The full content of the report, as a UTF-8 string.
    create_quarto_report <- function(filename, content) {
      dir.create(here::here("reports"), showWarnings = FALSE)
      dest <- file.path("reports", basename(filename))
      # TODO: Ensure UTF-8 encoding, even on Windows
      writeLines(content, dest)
      message("Saved report to ", dest)
      system2("quarto", c("render", dest))
      # change extension to .html
      rendered <- paste0(tools::file_path_sans_ext(dest), ".html")
      if (file.exists(rendered)) {
        message("Opening report in browser...")
        browseURL(rendered)
      }
      invisible(NULL)
    }

    # Executes R code in the current session
    #
    # @param code R code to execute
    # @returns The results of the evaluation
    # @noRd
    run_r_code <- function(code) {
      shiny::withLogErrors({
        at_line_start <- TRUE
        emit <- function(str, end = "\n\n") {
          str <- paste0(paste(str, collapse = "\n"), end)
          if (nchar(str) == 0) {
            return()
          }
          at_line_start <<- substr(str, nchar(str), nchar(str)) == "\n"
          chat_append_message("chat",
            list(role = "assistant", content = str),
            chunk = TRUE, operation = "append"
          )
        }

        # What gets returned to the LLM
        result <- list()
        # Buffered up text for the current code block
        txt_buffer <- character()
        in_code_block <- FALSE

        # If we're not in a code block, start one
        start_code_block <- function() {
          if (!in_code_block) {
            in_code_block <<- TRUE
            # use ```text to prevent client-side highlighting. If we don't do
            # this, the colors get pretty randomly assigned.
            emit("````text", end = "\n")
            stopifnot(length(txt_buffer) == 0)
          }
        }

        # If we're in a code block, end it (flush the buffer)
        end_code_block <- function() {
          if (in_code_block) {
            in_code_block <<- FALSE

            # For user
            if (!at_line_start) {
              # If the last thing in the buffer isn't a newline, add one.
              # If we don't do this then the code block might not end.
              emit("")
            }
            emit("````")

            # For model
            result <<- c(result, list(list(type = "text", text = paste0(
              "```\n",
              paste(txt_buffer, collapse = "\n\n"),
              "\n```"
            ))))

            txt_buffer <<- character()
          }
          invisible()
        }

        out_img <- function(media_type, b64data) {
          end_code_block()
          result <<- c(result, list(list(
            type = "image",
            source = list(
              type = "base64",
              media_type = media_type,
              data = b64data
            )
          )))
          emit(sprintf("![Plot](data:%s;base64,%s)", media_type, b64data))
        }

        out_df <- function(df) {
          end_code_block()
          # For the model
          df_json <- encode_df_for_model(df, max_rows = 100, show_end = 10)
          result <<- c(result, list(list(type = "text", text = df_json)))
          # For human
          # TODO: Make sure human sees same EXACT rows as model, this includes omitting the same rows
          op <- options(knitr.kable.max_rows = 100)
          on.exit(options(op), add = TRUE, after = FALSE)
          md_tbl <- paste0(
            collapse = "\n",
            knitr::kable(df, format = "html", table.attr = "class=\"data-frame table table-sm table-striped\"")
          )
          emit(md_tbl)
        }

        out_txt <- function(txt, end = "") {
          start_code_block()
          txt_buffer <<- c(txt_buffer, txt)
          emit(txt, end = end)
        }

        # # This doesn't work yet--shinychat can't show htmlwidgets
        # out_widget <- function(widget) {
        #   chat_append("chat",
        #     list(role = "assistant", content = htmltools::as.tags(widget)),
        #     chunk = TRUE, operation = "append"
        #   )
        # }

        emit(paste0("```r\n", code, "\n```"))

        # Use the new evaluate_r_code function
        evaluated <- evaluate_r_code(code)

        for (output in evaluated$outputs) {
          if (output$type == "source") {
            next # Skip source code since we already showed it
          } else if (output$type == "recordedplot") {
            out_img(output$mime, output$content)
          } else {
            if (output$type == "error") {
              out_txt(sprintf("Error: %s\n", paste(output$content, collapse = "\n")))
            } else if (output$type == "warning") {
              out_txt(sprintf("Warning: %s\n", paste(output$content, collapse = "\n")))
            } else if (output$type == "message") {
              out_txt(sprintf("%s\n", paste(output$content, collapse = "\n")))
            } else if (output$type == "text") {
              out_txt(output$content)
            } else if (output$type == "value") {
              if (inherits(output$value, "data.frame")) {
                out_df(output$value)
              # } else if (inherits(output$value, "htmlwidget")) {
              #   out_widget(output$value)
              } else {
                out_txt(output$content, end = "\n")
              }
            } else {
              out_txt(output$content, end = "\n")
            }
          }
        }

        # Flush the last code block, if any
        end_code_block()

        I(result)
      })
    }

    chat <- chat_claude(system_prompt, model = "claude-3-5-sonnet-latest", turns = default_turns)
    chat$register_tool(tool(
      run_r_code,
      "Executes R code in the current session",
      code = type_string("R code to execute")
    ))
    chat$register_tool(tool(
      create_quarto_report,
      "Creates a Quarto report and displays it to the user",
      filename = type_string("The desired filename of the report. Should end in `.qmd`."),
      content = type_string("The full content of the report, as a UTF-8 string.")
    ))

    observeEvent(input$chat_user_input, {
      stream <- chat$stream_async(input$chat_user_input)
      chat_append("chat", stream) |> promises::finally(~ {
        cat("\n\n\n")
        # print(chat)
        print(chat$tokens())
        message("Total input tokens: ", sum(chat$tokens()[, "input"]))
        message("Total output tokens: ", sum(chat$tokens()[, "output"]))
        message("Total tokens: ", sum(chat$tokens()))
        last_chat <<- chat
      })
    })
  }

  print(shinyApp(ui, server))
}