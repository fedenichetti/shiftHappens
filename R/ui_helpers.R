#' Bootstrap-styled status badge with curbcut-inspired left-border accent.
#' @param status one of "ready", "generating", "optimal", "feasible",
#'        "infeasible", "timeout"
#' @param label  display text
#' @return shiny tag
status_badge <- function(status, label) {
  color <- switch(status,
    optimal = , feasible = "#1ca5b8",
    infeasible = , timeout = "#c4302b",
    "#666666"
  )
  htmltools::div(
    style = paste0(
      "border-left: 4px solid ", color, ";",
      "padding: 0.75rem 1rem;",
      "font-weight: 700; font-size: 1.25rem;"
    ),
    label
  )
}

#' Render an issues tibble (from validate_inputs) as a Shiny-friendly bullet list.
#'
#' @param issues result of validate_inputs()
#' @param severity_filter "error" or "warning"
#' @return shiny tag (NULL if no rows match)
issues_panel <- function(issues, severity_filter) {
  rows <- issues[issues$severity == severity_filter, ]
  if (nrow(rows) == 0) return(NULL)
  htmltools::tags$ul(
    lapply(seq_len(nrow(rows)), function(i) {
      htmltools::tags$li(
        sprintf("[%s row %s] %s",
          rows$sheet[i],
          ifelse(is.na(rows$row[i]), "-", as.character(rows$row[i])),
          rows$message[i]
        )
      )
    })
  )
}
