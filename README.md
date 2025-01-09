# Databot: Data exploration assistant for R

Trying to make sense of a new pile of CSVs? Got a vision for a plot but can't quite figure out the right ggplot2 calls? Feeling stuck on finding interesting questions to ask of your data?

Databot is an experimental AI assistant that is designed to come alongside you, and help you by performing tasks within your R session.

## Features

- Point Databot at some data and it will come up with plenty of ideas of how to analyze it.
- Most interactions with Databot end with it making multiple suggestions about what to do next; you can click these suggestions to prepopulate the input prompt.
- Databot answers your questions by generating R code, and running it in your current R session. When it does, the source code and results are seen by both you, the user, and Databot itself. This includes plots, tables, etc.
- If your chat with Databot has yielded useful insights, you can ask it to distill your chat session into a reproducible Quarto report.

## Setup

### API Key

Databot uses Claude 3.5 Sonnet, so you will need an `ANTHROPIC_API_KEY` environment variable (get an API key [here](https://console.anthropic.com/settings/keys)). Using an .Renviron file is one way to do that--but be sure to .gitignore it!

### Package installation

```r
pak::pak("jcheng5/databot")
```

## Running

- Open a (new or existing) project in RStudio or Positron.
- \[Optional\] If this is an existing project, you can add an `llms.txt` file to the root of the project to tell the LLM whatever you think it should know. Like a README.md, but targeted at the LLM. (TODO: Maybe we should just read the README?)
- **Run `databot::chat()` to launch the app.**

## Limitations

- Pretty fragile currently; if the Shiny app greys out, there is no way to recover the current chat session. Same if an Anthropic API call errors out for some reason on their end (such as being bounced due to too much traffic on their end).
- No [HTML Widget](https://htmlwidgets.org) support at this time, so no Plotly, Leaflet, DT, etc.
- When generating a report, there's not much progress indication currently.
