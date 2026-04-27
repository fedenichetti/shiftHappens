mod_schedule_view_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::uiOutput(ns("status")),
    shiny::uiOutput(ns("infeasibility")),
    shiny::conditionalPanel(
      ns = ns, condition = "output.has_schedule == true",
      shiny::h3(i18n_it$schedule_title),
      DT::DTOutput(ns("schedule_dt")),
      shiny::h3(i18n_it$summary_title),
      DT::DTOutput(ns("summary_dt")),
      shiny::tags$details(
        shiny::tags$summary(i18n_it$diagnostics_title),
        DT::DTOutput(ns("diagnostics_dt"))
      ),
      shiny::downloadButton(ns("download"), i18n_it$download,
                             class = "btn btn-primary")
    )
  )
}

mod_schedule_view_server <- function(id, result, ctx) {
  shiny::moduleServer(id, function(input, output, session) {
    output$has_schedule <- shiny::reactive({
      r <- result()
      !is.null(r) && !is.null(r$schedule)
    })
    shiny::outputOptions(output, "has_schedule", suspendWhenHidden = FALSE)

    output$status <- shiny::renderUI({
      r <- result()
      if (is.null(r)) return(NULL)
      if (!is.null(r$schedule)) {
        status_badge("optimal", i18n_it$status_optimal)
      } else {
        status_badge("infeasible", i18n_it$status_infeasible)
      }
    })

    output$infeasibility <- shiny::renderUI({
      r <- result()
      if (is.null(r) || !is.null(r$schedule)) return(NULL)
      diag_row <- r$diagnostics$value[r$diagnostics$field == "infeasibility_diagnosis"]
      if (length(diag_row) == 0) return(NULL)
      shiny::tagList(
        shiny::h4(i18n_it$status_infeasible),
        shiny::p(diag_row)
      )
    })

    output$schedule_dt <- DT::renderDT({
      shiny::req(result()$schedule)
      DT::datatable(result()$schedule,
        rownames = FALSE, options = list(dom = "t", pageLength = 31))
    })
    output$summary_dt <- DT::renderDT({
      shiny::req(result()$summary)
      DT::datatable(result()$summary, rownames = FALSE,
        options = list(dom = "t"))
    })
    output$diagnostics_dt <- DT::renderDT({
      shiny::req(result()$diagnostics)
      DT::datatable(result()$diagnostics, rownames = FALSE,
        options = list(dom = "t"))
    })

    output$download <- shiny::downloadHandler(
      filename = function() {
        sprintf("shifthappens_%s.xlsx", format(Sys.Date(), "%Y-%m-%d"))
      },
      content = function(file) {
        shiny::req(result())
        r <- result()
        c <- ctx()
        holidays <- if (!is.null(c)) {
          h <- holidays_for_year(
            lubridate::year(c$calendar$date[1]),
            holidays_extra = c$rules$holidays_extra
          )
          h$date
        } else NULL
        write_output_workbook(file, r$schedule, r$summary, r$diagnostics,
                              holiday_dates = holidays)
      }
    )
  })
}
