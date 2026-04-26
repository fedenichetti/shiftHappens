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

#' Build per-day slot table for a target month.
#'
#' Each row of the returned tibble represents one calendar day with:
#'   - is_holiday: TRUE if the date is in the national list or in
#'                 holidays_extra
#'   - slot_kind:  "weekday"  (Mon-Fri non-holiday)
#'                 "weekend"  (Sat/Sun non-holiday)
#'                 "holiday"  (any day that is a holiday — collapsed to
#'                            weekend slot structure per spec §4.7)
#'   - slots:      list-column; each cell is a tibble of slots present
#'                 on that day with columns (role, period)
#'
#' @param year integer
#' @param month integer 1-12
#' @param holidays_extra list passed to holidays_for_year
#' @return tibble (one row per day)
build_calendar <- function(year, month, holidays_extra = NULL) {
  d <- month_days(year, month)
  holidays <- holidays_for_year(year, holidays_extra = holidays_extra)
  d$is_holiday <- d$date %in% holidays$date

  d$slot_kind <- ifelse(
    d$is_holiday, "holiday",
    ifelse(d$is_weekend, "weekend", "weekday")
  )

  d$slots <- purrr::map(d$slot_kind, slots_for_kind)
  d
}

#' Slot template for a slot_kind. Internal helper.
#'
#' weekday slots: one 12h night per role (1° + 2°) = 2 slots
#' weekend/holiday slots: day + night per role = 4 slots
slots_for_kind <- function(kind) {
  switch(kind,
    weekday = tibble::tibble(
      role   = c("first", "second"),
      period = c("night", "night")
    ),
    weekend = ,
    holiday = tibble::tibble(
      role   = c("first", "first", "second", "second"),
      period = c("day",   "night", "day",    "night")
    ),
    stop("unknown slot_kind: ", kind)
  )
}
