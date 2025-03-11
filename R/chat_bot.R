chat_bot <- function(system_prompt = NULL, default_turns = list()) {
  chat <- chat_claude(
    system_prompt,
    model = "claude-3-5-sonnet-latest",
    turns = default_turns,
    echo = FALSE
  )
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
  chat  
}
