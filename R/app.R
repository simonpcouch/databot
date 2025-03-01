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
        out <- MarkdownStreamer$new(function(md_text) {
          chat_append_message("chat",
            list(role = "assistant", content = md_text),
            chunk = TRUE, operation = "append"
          )
        })
        on.exit(out$close(), add = TRUE, after = FALSE)

        # What gets returned to the LLM
        result <- list()

        out_img <- function(media_type, b64data) {
          result <<- c(result, list(list(
            type = "image",
            source = list(
              type = "base64",
              media_type = media_type,
              data = b64data
            )
          )))
          out$md(sprintf("![Plot](data:%s;base64,%s)", media_type, b64data), TRUE, TRUE)
        }

        out_df <- function(df) {
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
          out$md(md_tbl, TRUE, TRUE)
        }

        out_txt <- function(txt, end = NULL) {
          txt <- paste(txt, collapse = "\n")
          if (txt == "") {
            return()
          }
          if (!is.null(end)) {
            txt <- paste0(txt, end)
          }
          result <<- c(result, list(list(type = "text", text = txt)))
          out$code(txt)
        }

        out$code(code)
        # End the source code block so the outputs all appear in a separate block
        out$close()

        # Use the new evaluate_r_code function
        evaluate_r_code(code, on_console_out = out_txt, on_console_err = out_txt, on_plot = out_img, on_dataframe = out_df)

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

    start_chat_request <- function(user_input) {
      stream <- chat$stream_async(user_input)
      chat_append("chat", stream) |> promises::finally(~ {
        cat("\n\n\n")
        # print(chat)
        print(chat$tokens())
        message("Total input tokens: ", sum(chat$tokens()[, "input"]))
        message("Total output tokens: ", sum(chat$tokens()[, "output"]))
        message("Total tokens: ", sum(chat$tokens()))
        last_chat <<- chat
      })
    }

    observeEvent(input$chat_user_input, {
      start_chat_request(input$chat_user_input)
    })

    # Kick start the chat session
    start_chat_request("Hello")
  }

  print(shinyApp(ui, server))
}