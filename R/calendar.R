#' Enumerate days of a calendar month with weekday and weekend flags.
#'
#' @param year integer
#' @param month integer 1-12
#' @return tibble with columns:
#'   date       Date
#'   weekday    integer 1 (Mon) .. 7 (Sun)
#'   is_weekend logical (TRUE for Sat/Sun)
month_days <- function(year, month) {
  stopifnot(is.numeric(year), is.numeric(month), month >= 1, month <= 12)
  start <- as.Date(sprintf("%04d-%02d-01", year, month))
  end   <- seq(start, by = "month", length.out = 2)[2] - 1L
  dates <- seq(start, end, by = "day")
  wday  <- as.integer(format(dates, "%u"))   # 1=Mon, 7=Sun (POSIX %u)
  tibble::tibble(
    date = dates,
    weekday = wday,
    is_weekend = wday %in% c(6L, 7L)
  )
}
