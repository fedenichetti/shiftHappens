#' Build the user-facing output workbook with three sheets.
#'
#' Schedule sheet shades weekend rows (`weekday %in% c("S","D")`) in light
#' grey to mirror the constraints doc's convention. Summary and diagnostics
#' get default formatting.
#'
#' If `schedule` and `summary` are NULL (infeasible solve), only the
#' `diagnostics` sheet is written — the workbook is still valid and the
#' caposala can read why generation failed.
#'
#' @param path destination .xlsx
#' @param schedule schedule tibble from postprocess_solution (or NULL)
#' @param summary  summary tibble (or NULL)
#' @param diagnostics diagnostics tibble (always present)
#' @return invisibly, the path
write_output_workbook <- function(path, schedule, summary, diagnostics) {
  wb <- openxlsx2::wb_workbook()

  if (!is.null(schedule)) {
    wb <- openxlsx2::wb_add_worksheet(wb, "schedule")
    wb <- openxlsx2::wb_add_data(wb, sheet = "schedule", x = schedule)
    weekend_rows <- which(schedule$weekday %in% c("S", "D"))
    if (length(weekend_rows) > 0) {
      # +1 to account for header row (openxlsx2 dims are 1-indexed)
      wb <- openxlsx2::wb_add_fill(wb, sheet = "schedule",
        dims = openxlsx2::wb_dims(rows = weekend_rows + 1, cols = seq_len(ncol(schedule))),
        color = openxlsx2::wb_color("#f7f7f7")
      )
    }
  }

  if (!is.null(summary)) {
    wb <- openxlsx2::wb_add_worksheet(wb, "summary")
    wb <- openxlsx2::wb_add_data(wb, sheet = "summary", x = summary)
  }

  wb <- openxlsx2::wb_add_worksheet(wb, "diagnostics")
  wb <- openxlsx2::wb_add_data(wb, sheet = "diagnostics", x = diagnostics)

  openxlsx2::wb_save(wb, path)
  invisible(path)
}
