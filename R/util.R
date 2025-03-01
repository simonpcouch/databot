as_str <- function(..., collapse = "\n", sep = "") {
  # Collapse each character vector in ..., then concatenate
  lst <- rlang::list2(...)
  strings <- vapply(lst, paste, character(1), collapse = collapse)
  paste(strings, collapse = sep)
}
