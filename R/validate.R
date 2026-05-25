#' Validate parsed workbook content for cross-sheet integrity.
#'
#' Returns a tibble (severity, sheet, row, column, message). Severity is
#' "error" (blocks generation) or "warning" (informational). The UI
#' disables the Generate button if any error rows are present.
#'
#' @param wb result of read_workbook()
#' @return tibble of issues (possibly zero rows)
validate_inputs <- function(wb) {
  issues <- list()
  add <- function(severity, sheet, row, column, message) {
    issues[[length(issues) + 1L]] <<- tibble::tibble(
      severity = severity, sheet = sheet, row = row,
      column = column, message = message
    )
  }

  # operators: enough seniors and 2°
  if (sum(wb$operators$role == "senior") < 1) {
    add("error", "operators", NA_integer_, "role",
        "must have at least 1 senior operator")
  }
  if (sum(wb$operators$role %in% c("nurse_2", "oss_2")) < 1) {
    add("error", "operators", NA_integer_, "role",
        "must have at least 1 secondary (nurse_2/oss_2) operator")
  }

  known_ops <- .resolve_operator_ids(wb$operators)

  # history operator references
  for (i in seq_len(nrow(wb$history))) {
    op <- wb$history$operator_id[i]
    if (!op %in% known_ops) {
      add("error", "history", i, "operator_id",
          sprintf("operator_id '%s' not in operators sheet", op))
    }
    slot <- wb$history$slot[i]
    if (!slot %in% c("weekday_night", "weekend_day", "weekend_night",
                     "holiday_day", "holiday_night")) {
      add("error", "history", i, "slot",
          sprintf("invalid slot '%s'", slot))
    }
    rs <- wb$history$role_slot[i]
    if (!rs %in% c("first", "second")) {
      add("error", "history", i, "role_slot",
          sprintf("role_slot must be 'first' or 'second', got '%s'", rs))
    }
  }

  # absences: operator references + date order
  for (i in seq_len(nrow(wb$absences))) {
    op <- wb$absences$operator_id[i]
    if (!op %in% known_ops) {
      add("error", "absences", i, "operator_id",
          sprintf("operator_id '%s' not in operators sheet", op))
    }
    if (!is.na(wb$absences$date_from[i]) && !is.na(wb$absences$date_to[i]) &&
        wb$absences$date_from[i] > wb$absences$date_to[i]) {
      add("error", "absences", i, "date_to",
          "date_from > date_to")
    }
  }

  # preferences: enums + range
  for (i in seq_len(nrow(wb$preferences))) {
    op <- wb$preferences$operator_id[i]
    if (!op %in% known_ops) {
      add("error", "preferences", i, "operator_id",
          sprintf("operator_id '%s' not in operators sheet", op))
    }
    wd <- wb$preferences$weekday[i]
    if (!is.na(wd) && (wd < 1L || wd > 7L)) {
      add("error", "preferences", i, "weekday",
          sprintf("weekday must be 1-7 or blank, got %s", wd))
    }
    st <- wb$preferences$slot_type[i]
    if (!is.na(st) && !st %in% c("day", "night")) {
      add("error", "preferences", i, "slot_type",
          sprintf("slot_type must be 'day', 'night', or blank, got '%s'", st))
    }
    pol <- wb$preferences$polarity[i]
    if (!pol %in% c("avoid", "prefer")) {
      add("error", "preferences", i, "polarity",
          sprintf("polarity must be 'avoid' or 'prefer', got '%s'", pol))
    }
  }

  # month: parseable + not in past
  m <- wb$month$month[1]
  m_parsed <- suppressWarnings(lubridate::ym(m))
  if (is.na(m_parsed)) {
    add("error", "month", 1L, "month",
        sprintf("not parseable as YYYY-MM: '%s'", m))
  } else {
    today_month <- lubridate::floor_date(Sys.Date(), "month")
    if (m_parsed < today_month) {
      add("error", "month", 1L, "month",
          sprintf("target month %s is in the past", m))
    }
  }

  if (length(issues) == 0) {
    return(tibble::tibble(
      severity = character(), sheet = character(),
      row = integer(), column = character(), message = character()
    ))
  }
  dplyr::bind_rows(issues)
}

#' Build the set of valid operator_id strings from the operators sheet.
#' If a surname is unique, it's a valid id; otherwise must be surname_name.
#' @param operators tibble
#' @return character vector
.resolve_operator_ids <- function(operators) {
  surnames <- operators$surname
  dupes <- surnames[duplicated(surnames)]
  ids <- character()
  for (i in seq_len(nrow(operators))) {
    s <- operators$surname[i]
    n <- operators$name[i]
    if (s %in% dupes) {
      ids <- c(ids, paste(s, n, sep = "_"))
    } else {
      ids <- c(ids, s)
    }
  }
  unique(c(surnames, ids))   # accept either form for non-duped surnames
}
