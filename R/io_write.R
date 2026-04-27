#' Build the user-facing output workbook with three sheets.
#'
#' Schedule sheet shades weekend rows (Sat/Sun, Italian letters "S"/"D")
#' AND any rows whose date is in `holiday_dates` (per spec §5.2.1: rows for
#' Saturday, Sunday, AND holidays are shaded). Light grey #f7f7f7 to mirror
#' the constraints doc's convention.
#'
#' All three sheets are always created, even on infeasible solve runs.
#' When `schedule` or `summary` are NULL, an empty placeholder sheet with
#' only headers is written; the diagnostics sheet carries the user-visible
#' explanation.
#'
#' @param path destination .xlsx
#' @param schedule schedule tibble from postprocess_solution (or NULL)
#' @param summary  summary tibble (or NULL)
#' @param diagnostics diagnostics tibble (always present)
#' @param holiday_dates optional Date vector of weekday holidays in the
#'        target month; used only to extend weekend shading on the schedule
#'        sheet. If NULL or empty, only Sat/Sun are shaded.
#' @return invisibly, the path
write_output_workbook <- function(path, schedule, summary, diagnostics,
                                   holiday_dates = NULL) {
  wb <- openxlsx2::wb_workbook()

  # Schedule (always create the sheet; placeholder if NULL)
  wb <- openxlsx2::wb_add_worksheet(wb, "schedule")
  if (!is.null(schedule)) {
    wb <- openxlsx2::wb_add_data(wb, sheet = "schedule", x = schedule)
    shaded_rows <- which(
      schedule$weekday %in% c("S", "D") |
      (!is.null(holiday_dates) & schedule$date %in% holiday_dates)
    )
    if (length(shaded_rows) > 0 && ncol(schedule) > 0) {
      # +1 to account for header row (openxlsx2 dims are 1-indexed)
      wb <- openxlsx2::wb_add_fill(wb, sheet = "schedule",
        dims = openxlsx2::wb_dims(rows = shaded_rows + 1,
                                   cols = seq_len(ncol(schedule))),
        color = openxlsx2::wb_color("#f7f7f7")
      )
    }
  }

  # Summary (always create; empty placeholder if NULL)
  wb <- openxlsx2::wb_add_worksheet(wb, "summary")
  if (!is.null(summary)) {
    wb <- openxlsx2::wb_add_data(wb, sheet = "summary", x = summary)
  }

  # Diagnostics (always present)
  wb <- openxlsx2::wb_add_worksheet(wb, "diagnostics")
  wb <- openxlsx2::wb_add_data(wb, sheet = "diagnostics", x = diagnostics)

  openxlsx2::wb_save(wb, path)
  invisible(path)
}
