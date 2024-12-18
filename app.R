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
        md <- c(md, flush_and_add(sprintf("![Plot](data:%s,%s)", output$mime, output$content)))
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
  chat$register_tool(tool(
    run_r_code,
    "Executes R code in the current session",
    code = type_string("R code to execute")
  ))

  observeEvent(input$chat_user_input, {
    stream <- chat$stream_async(input$chat_user_input)
    chat_append("chat", stream) |> promises::finally(~{
      cat("\n\n\n")
      print(chat)
      print(chat$tokens())
      message("Total input tokens: ", sum(chat$tokens()[, "input"]))
      message("Total output tokens: ", sum(chat$tokens()[, "output"]))
      message("Total tokens: ", sum(chat$tokens()))
    })
  })
}

shinyApp(ui, server)