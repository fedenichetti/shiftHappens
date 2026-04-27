#' Shiny module: passcode gate.
#'
#' Reads APP_PASSCODE from the environment. If unset OR empty, the gate is
#' bypassed (development mode).
#'
#' Returns a reactive logical: TRUE once the user is authenticated.
mod_passcode_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::uiOutput(ns("gate"))
}

mod_passcode_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    expected <- Sys.getenv("APP_PASSCODE", "")
    authed <- shiny::reactiveVal(nchar(expected) == 0L)

    output$gate <- shiny::renderUI({
      if (authed()) return(NULL)
      shiny::div(
        style = "max-width: 400px; margin: 4rem auto;",
        shiny::h2(i18n_it$passcode_label),
        shiny::passwordInput(ns("code"), label = NULL),
        shiny::actionButton(ns("submit"), i18n_it$passcode_submit,
                            class = "btn btn-primary"),
        shiny::uiOutput(ns("error"))
      )
    })

    shiny::observeEvent(input$submit, {
      if (identical(input$code, expected)) {
        authed(TRUE)
      } else {
        output$error <- shiny::renderUI(
          shiny::div(style = "color: #c4302b; margin-top: 1rem;",
                     i18n_it$passcode_error)
        )
      }
    })

    authed
  })
}
