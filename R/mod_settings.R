mod_settings_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::dateInput(ns("month"), label = i18n_it$month_label,
                     value = lubridate::floor_date(Sys.Date() + 32, "month"),
                     format = "yyyy-mm"),
    shiny::actionButton(ns("generate"), i18n_it$generate,
                        class = "btn btn-primary",
                        style = "margin-top: 1rem;")
  )
}

mod_settings_server <- function(id, parsed, issues) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    can_generate <- shiny::reactive({
      !is.null(parsed()) && (
        is.null(issues()) ||
        sum(issues()$severity == "error") == 0L
      )
    })
    shiny::observe({
      shinyjs::toggleState(ns("generate"), condition = can_generate())
    })
    list(
      generate = shiny::reactive(input$generate),
      target_month = shiny::reactive(format(input$month, "%Y-%m"))
    )
  })
}
