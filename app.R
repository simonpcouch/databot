library(shiny)
library(bslib)
library(elmer)
library(shinychat)

stopifnot(packageVersion("shinychat") >= "0.1.0")
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
  layout_columns(
    chat_ui("chat", fill = TRUE, width = "100%", height = "100%"),
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
  
  chat <- chat_claude(system_prompt, model = "claude-3-5-sonnet-latest")

  observeEvent(input$chat_user_input, {
    llm_input <- list(input$chat_user_input)
    chat_append_message("chat", list(role = "assistant", content = ""), chunk = "start")
    on.exit(chat_append_message("chat", list(role = "assistant", content = ""), chunk = "end"))
    emit <- function(text) {
      chat_append_message("chat", list(role = "assistant", content = paste0(text, "\n\n")), chunk = TRUE)
    }

    while (TRUE) {
      resp <- chat$extract_data(!!!llm_input, type = type_object(
        "The response to send back to the user; can include markdown and/or R code for the user to execute and send back the results. If both are provided, the markdown will be displayed before the code is displayed and run.",
        markdown = type_string("Markdown to display before the R code is executed.", required = TRUE),
        r_code = type_string("R code to execute and display the results.", required = FALSE)
      ))
      if (is.character(resp)) {
        if (substr(resp, 1, 1) == "{") {
          stop("Model returned a string where we expected an object! Interpreting as JSON.")
          if (substr(resp, nchar(resp), nchar(resp)) == ">") {
            # strip trailing >
            warning("Model returned malformed JSON (trailing >)")
            resp <- substr(resp, 1, nchar(resp) - 1)
          }
          resp <- jsonlite::parse_json(resp)
        } else {
          stop("Model returned a string where we expected an object! Interpreting as Markdown.")
          resp <- list(markdown = resp)
        }
      }
      if (!is.null(resp$markdown)) {
        emit(resp$markdown)
      }
      if (!is.null(resp$r_code)) {
        emit(paste(c("```r", resp$r_code, "```\n"), collapse = "\n"))
        result <- evaluate_r_code(resp$r_code)
        parts <- output_to_elmer_content(result)
        for (part in parts) {
          if (inherits(part, "elmer::ContentText")) {
            emit(paste(collapse = "\n", c("```", part@text, "```")))
          } else if (inherits(part, "elmer::ContentImageInline")) {
            emit(sprintf("<div class=\"plot-container\"><img alt=\"A plot\" src=\"data:%s;base64,%s\"></div>", part@type, part@data))
          } else {
            stop("Unknown part type: ", class(part)[[1]])
          }
        }
        llm_input <- c(list("<R_CODE_RESULTS>\n"), parts, list("</R_CODE_RESULTS>\n"))
        next
      }
      break
    }
    cat("\n\n\n")
    # print(chat)
    print(chat$tokens())
    message("Total input tokens: ", sum(chat$tokens()[, "input"]))
    message("Total output tokens: ", sum(chat$tokens()[, "output"]))
    message("Total tokens: ", sum(chat$tokens()))
  })
}

shinyApp(ui, server)