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

    chat <- chat_bot(system_prompt, default_turns)
    start_chat_request <- function(user_input) {
      stream <- chat$stream_async(user_input)
      chat_append("chat", stream) |> promises::finally(~ {
        tokens <- chat$tokens(include_system_prompt = FALSE)
        input <- sum(tokens$tokens[tokens$role == "user"])
        output <- sum(tokens$tokens[tokens$role == "assistant"])

        cat("\n")
        cat(rule("Turn ", nrow(tokens) / 2), "\n", sep = "")
        cat("Total input tokens:  ", input, "\n", sep = "")
        cat("Total output tokens: ", output, "\n", sep = "")
        cat("Total tokens:        ", input + output, "\n", sep = "")
        cat("\n")
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
