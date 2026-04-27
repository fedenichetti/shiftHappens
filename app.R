# Source all R/ files (no library() calls inside R/*.R; we qualify everything)
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

library(shiny)
library(bslib)

rules_path <- Sys.getenv("RULES_CONFIG_PATH", "config/rules.yaml")
rules <- load_rules(rules_path)

theme <- bslib::bs_theme(
  version = 5,
  bg = "#ffffff",
  fg = "#111111",
  primary = rules$ui$primary_color,
  base_font = bslib::font_collection(
    "Inter", "system-ui", "-apple-system", "Segoe UI", "Helvetica"
  ),
  heading_font = bslib::font_collection("Inter", "system-ui"),
  font_scale = 1.0
)

ui <- bslib::page_sidebar(
  title = htmltools::tags$div(
    style = "font-weight: 700; font-size: 1.5rem; letter-spacing: -0.02em;",
    paste(i18n_it$app_title, "—", rules$unit$name)
  ),
  theme = theme,
  shinyjs::useShinyjs(),
  sidebar = bslib::sidebar(
    mod_upload_ui("upload"),
    mod_settings_ui("settings"),
    shiny::actionButton("restart", i18n_it$start_over,
                        class = "btn btn-link",
                        style = "margin-top: 1rem; padding: 0; text-align: left;")
  ),
  mod_passcode_ui("gate"),
  shiny::uiOutput("authed_app")
)

server <- function(input, output, session) {
  authed <- mod_passcode_server("gate")

  output$authed_app <- shiny::renderUI({
    if (!isTRUE(authed())) return(NULL)
    mod_schedule_view_ui("view")
  })

  upload <- mod_upload_server("upload", rules)
  settings <- mod_settings_server("settings", upload$parsed, upload$issues)

  ctx_reactive <- shiny::eventReactive(settings$generate(), {
    shiny::req(upload$parsed())
    target <- settings$target_month()
    yr <- as.integer(substr(target, 1, 4))
    mo <- as.integer(substr(target, 6, 7))
    cal <- build_calendar(yr, mo, holidays_extra = rules$holidays_extra)
    ctx <- build_model_context(upload$parsed(), rules, cal)
    ctx$preferences <- upload$parsed()$preferences
    ctx
  })

  result <- shiny::eventReactive(settings$generate(), {
    shiny::req(upload$parsed())
    shiny::withProgress(message = i18n_it$generating, value = NULL, {
      ctx <- ctx_reactive()
      m <- build_milp(ctx)
      sol <- solve_milp(m,
        time_limit_seconds = rules$solver$time_limit_seconds)
      postprocess_solution(sol, ctx)
    })
  })

  shiny::observeEvent(input$restart, {
    session$reload()
  })

  mod_schedule_view_server("view", result, ctx_reactive)
}

shinyApp(ui, server)
