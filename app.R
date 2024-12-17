library(shiny)
library(bslib)
library(elmer)
library(shinychat)

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
  layout_columns(
    chat_ui("chat", fill = TRUE, height = "100%"),
    # div(id="output_container")
  )
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
  
  #' Executes R code in the current session
  #' 
  #' @param code R code to execute
  #' @returns The results of the evaluation
  run_r_code <- function(code) {
    msg <- list(
      role = "assistant",
      content = paste0("```r\n", code, "\n```\n")
    )
    chat_append_message("chat", msg, chunk = TRUE, operation = "append", session = session)
    
    # Use the new evaluate_r_code function
    result <- evaluate_r_code(code)
    
    # Format the outputs as markdown
    md <- character()
    text_buffer <- character()
    
    # Helper function to flush text buffer and add special output
    flush_and_add <- function(special_output = NULL) {
      result <- character()
      if (length(text_buffer) > 0) {
        result <- c(result, paste0("```\n", paste(text_buffer, collapse = "\n"), "\n```"))
      }
      if (!is.null(special_output)) {
        result <- c(result, special_output)
      }
      result
    }
    
    for (output in result$outputs) {
      if (output$type == "source") {
        next  # Skip source code since we already showed it
      } else if (output$type == "recordedplot") {
        md <- c(md, flush_and_add(sprintf("![Plot](data:%s;base64,%s)", output$mime, output$content)))
        text_buffer <- character()
      } else {
        if (output$type == "error") {
          md <- c(md, flush_and_add(sprintf("**Error:** %s", paste(output$content, collapse = "\n"))))
          text_buffer <- character()
        } else if (output$type == "warning") {
          md <- c(md, flush_and_add(sprintf("**Warning:** %s", paste(output$content, collapse = "\n"))))
          text_buffer <- character()
        } else if (output$type == "message") {
          md <- c(md, flush_and_add(sprintf("*Message:* %s", paste(output$content, collapse = "\n"))))
          text_buffer <- character()
        } else {
          # Accumulate text output in the buffer
          text_buffer <- c(text_buffer, output$content)
        }
      }
    }
    
    # Flush any remaining text in the buffer
    md <- c(md, flush_and_add())
    
    if (length(md) > 0) {
      msg <- list(
        role = "assistant",
        content = paste(md, collapse = "\n\n")
      )
      chat_append_message("chat", msg, chunk = TRUE, operation = "append", session = session)
    }
    
    paste(md, collapse = "\n\n")
  }

  chat <- chat_claude(system_prompt, model = "claude-3-5-sonnet-latest")

  observeEvent(input$chat_user_input, {
    llm_input <- list(input$chat_user_input)
    while (TRUE) {
      resp <- chat$extract_data(!!!llm_input, type = type_object(
        "The response to send back to the user; can include markdown and/or R code for the user to execute and send back the results. If both are provided, the markdown will be displayed before the code is displayed and run.",
        markdown = type_string("Markdown to display before the R code is executed.", required = TRUE),
        r_code = type_string("R code to execute and display the results.", required = FALSE)
      ))
      if (!is.null(resp$markdown)) {
        chat_append("chat", resp$markdown)
      }
      if (!is.null(resp$r_code)) {
        chat_append("chat", paste(c("```r", resp$r_code, "```\n"), collapse = "\n"))
        result <- evaluate_r_code(resp$r_code)
        parts <- output_to_elmer_content(result)
        chat_append_message("chat", list(role = "assistant", content = ""), chunk = "start")
        for (part in parts) {
          if (inherits(part, "elmer::ContentText")) {
            chat_append_message("chat", list(role = "assistant", content = part@text), chunk = TRUE)
          } else if (inherits(part, "elmer::ContentImageInline")) {
            chat_append_message("chat", list(role = "assistant", content = sprintf("<img alt=\"A plot\" src=\"data:%s;base64,%s\">", part@type, part@data)), chunk = TRUE)
          } else {
            stop("Unknown part type: ", class(part)[[1]])
          }
        }
        chat_append_message("chat", list(role = "assistant", content = ""), chunk = "end")
        llm_input <- parts
        next
      }
      break
    }
    cat("\n\n\n")
    print(chat)
    print(chat$tokens())
    message("Total input tokens: ", sum(chat$tokens()[, "input"]))
    message("Total output tokens: ", sum(chat$tokens()[, "output"]))
    message("Total tokens: ", sum(chat$tokens()))
  })
}

shinyApp(ui, server)