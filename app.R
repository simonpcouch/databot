library(shiny)
library(bslib)
library(elmer)
library(shinychat)

options(elmer_verbosity = 2)

local(env = globalenv(), {
  if (!file.exists("data/book.csv")) {
    stop("Run download_data.R first")
  }
  book <- readr::read_csv('data/book.csv')
  broadcast_media <- readr::read_csv('data/broadcast_media.csv')
  journalism <- readr::read_csv('data/journalism.csv')
  leadership <- readr::read_csv('data/leadership.csv')
  restaurant_and_chef <- readr::read_csv('data/restaurant_and_chef.csv')
})

source("functions.R")

ui <- page_fillable(
  tags$link(href = "style.css", rel = "stylesheet"),
  chat_ui("chat", fill = TRUE, height = "100%", width = "100%")
)

server <- function(input, output, session) {
  ctx_vars <- describe_vars(c("book", "broadcast_media", "journalism", "leadership", "restaurant_and_chef"))
  system_prompt <- paste(
    c(
      readLines("prompt.md", warn = FALSE),
      "\n\n",
      ctx_vars
    ), 
    collapse = "\n"
  )

  #' Creates a Quarto report and displays it to the user
  #'
  #' @param filename The desired filename of the report. Should end in `.qmd`.
  #' @param content The full content of the report, as a UTF-8 string.
  create_quarto_report <- function(filename, content) {
    dest <- tempfile(tools::file_path_sans_ext(filename), fileext = ".qmd")
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
  
  #' Executes R code in the current session
  #' 
  #' @param code R code to execute
  #' @returns The results of the evaluation
  run_r_code <- function(code) {shiny::withLogErrors({
    chat_append_message("chat", list(role = "assistant", content = ""), chunk = "start")
    on.exit(chat_append_message("chat", list(role = "assistant", content = ""), chunk = "end"))
    emit <- function(str, end = "\n\n") {
      str <- paste0(paste(str, collapse = "\n"), end)
      chat_append_message("chat", list(role = "assistant", content = str), chunk = TRUE, operation = "append")
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
        emit("```", end = "\n")
        stopifnot(length(txt_buffer) == 0)
      }
    }

    # If we're in a code block, end it (flush the buffer)
    end_code_block <- function() {
      if (in_code_block) {
        in_code_block <<- FALSE

        # For user
        emit("```")

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
      result <<- c(result, list(list(type = "text", text = jsonlite::toJSON(df))))
      # For human
      md_tbl <- paste0(collapse = "\n",
        knitr::kable(df, format = "html", table.attr = "class=\"data-frame table table-sm table-striped\"")
      )
      emit(md_tbl)
    }

    out_txt <- function(txt) {
      start_code_block()
      txt_buffer <<- c(txt_buffer, txt)
      emit(txt)
    }

    emit(paste0("```r\n", code, "\n```"))

    # Use the new evaluate_r_code function
    evaluated <- evaluate_r_code(code)
    
    for (output in evaluated$outputs) {
      if (output$type == "source") {
        next  # Skip source code since we already showed it
      } else if (output$type == "recordedplot") {
        out_img(output$mime, output$content)
      } else {
        if (output$type == "error") {
          out_txt(sprintf("Error: %s", paste(output$content, collapse = "\n")))
        } else if (output$type == "warning") {
          out_txt(sprintf("Warning: %s", paste(output$content, collapse = "\n")))
        } else if (output$type == "message") {
          out_txt(sprintf("%s", paste(output$content, collapse = "\n")))
        } else if (output$type == "text") {
          out_txt(output$content)
        } else if (output$type == "value") {
          if (inherits(output$value, "data.frame")) {
            out_df(output$value)
          } else {
            out_txt(output$content)
          }
        } else {
          out_txt(output$content)
        }
      }
    }

    # Flush the last code block, if any
    end_code_block()
    
    I(result)
  })}

  chat <- chat_claude(system_prompt, model = "claude-3-5-sonnet-latest")
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
    chat_append("chat", stream) |> promises::finally(~{
      cat("\n\n\n")
      # print(chat)
      print(chat$tokens())
      message("Total input tokens: ", sum(chat$tokens()[, "input"]))
      message("Total output tokens: ", sum(chat$tokens()[, "output"]))
      message("Total tokens: ", sum(chat$tokens()))
    })
  })
}

shinyApp(ui, server)