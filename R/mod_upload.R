mod_upload_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::fileInput(ns("file"), label = i18n_it$upload_label,
                     accept = ".xlsx", buttonLabel = i18n_it$upload_drop_hint),
    shiny::uiOutput(ns("validation"))
  )
}

mod_upload_server <- function(id, rules) {
  shiny::moduleServer(id, function(input, output, session) {
    parsed <- shiny::reactiveVal(NULL)
    issues <- shiny::reactiveVal(NULL)

    shiny::observeEvent(input$file, {
      shiny::req(input$file)
      wb <- tryCatch(read_workbook(input$file$datapath),
                     error = function(e) e)
      if (inherits(wb, "error")) {
        parsed(NULL)
        issues(tibble::tibble(
          severity = "error", sheet = "-", row = NA_integer_,
          column = "-", message = conditionMessage(wb)
        ))
        return()
      }
      parsed(wb)
      issues(validate_inputs(wb))
    })

    output$validation <- shiny::renderUI({
      iss <- issues()
      if (is.null(iss)) return(NULL)
      err  <- iss[iss$severity == "error", ]
      warn <- iss[iss$severity == "warning", ]
      shiny::tagList(
        if (nrow(err) > 0) shiny::tagList(
          shiny::h4(i18n_it$validation_errors,
                    style = "color:#c4302b;"),
          issues_panel(iss, "error")
        ) else shiny::h4(i18n_it$validation_ok,
                          style = "color:#1ca5b8;"),
        if (nrow(warn) > 0) shiny::tagList(
          shiny::h4(i18n_it$validation_warnings, style = "color:#aa8800;"),
          issues_panel(iss, "warning")
        )
      )
    })

    list(parsed = parsed, issues = issues)
  })
}
