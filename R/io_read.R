#' Required sheet names for the input workbook.
.required_sheets <- c("operators", "history", "absences", "preferences", "month")

#' Read all 5 sheets of the input workbook.
#'
#' Returns a named list of tibbles. Type coercion is best-effort:
#'   - dates parsed via lubridate::as_date
#'   - integers coerced from numeric where appropriate
#'   - all character columns trimmed of leading/trailing whitespace
#'
#' Throws an error if any required sheet is missing.
#'
#' @param path Path to .xlsx
#' @return named list (operators, history, absences, preferences, month)
read_workbook <- function(path) {
  if (!file.exists(path)) stop("workbook not found: ", path)
  sheets <- readxl::excel_sheets(path)
  missing <- setdiff(.required_sheets, sheets)
  if (length(missing) > 0) {
    stop("missing required sheet(s): ", paste(missing, collapse = ", "))
  }

  out <- list()
  out$operators   <- .read_operators(path)
  out$history     <- .read_history(path)
  out$absences    <- .read_absences(path)
  out$preferences <- .read_preferences(path)
  out$month       <- .read_month(path)
  out
}

.read_operators <- function(path) {
  ops <- readxl::read_excel(path, sheet = "operators")
  ops$surname <- trimws(as.character(ops$surname))
  ops$name    <- trimws(as.character(ifelse(is.na(ops$name), "", ops$name)))
  ops$role    <- trimws(as.character(ops$role))
  if (is.null(ops$part_time_pct)) ops$part_time_pct <- 100L
  ops$part_time_pct <- as.integer(ops$part_time_pct)
  if (is.null(ops$active_from)) ops$active_from <- as.Date("1900-01-01")
  ops$active_from <- lubridate::as_date(ops$active_from)
  if (is.null(ops$active_to)) ops$active_to <- as.Date("9999-12-31")
  ops$active_to <- lubridate::as_date(ops$active_to)
  tibble::as_tibble(ops)
}

.read_history <- function(path) {
  h <- readxl::read_excel(path, sheet = "history")
  if (nrow(h) == 0) {
    return(tibble::tibble(
      date = as.Date(character()),
      slot = character(),
      role_slot = character(),
      operator_id = character()
    ))
  }
  h$date <- lubridate::as_date(h$date)
  h$slot <- as.character(h$slot)
  h$role_slot <- as.character(h$role_slot)
  h$operator_id <- trimws(as.character(h$operator_id))
  tibble::as_tibble(h)
}

.read_absences <- function(path) {
  a <- readxl::read_excel(path, sheet = "absences")
  if (nrow(a) == 0) {
    return(tibble::tibble(
      operator_id = character(),
      date_from = as.Date(character()),
      date_to = as.Date(character()),
      type = character()
    ))
  }
  a$operator_id <- trimws(as.character(a$operator_id))
  a$date_from <- lubridate::as_date(a$date_from)
  a$date_to <- lubridate::as_date(a$date_to)
  a$type <- as.character(a$type)
  tibble::as_tibble(a)
}

.read_preferences <- function(path) {
  p <- readxl::read_excel(path, sheet = "preferences")
  if (nrow(p) == 0) {
    return(tibble::tibble(
      operator_id = character(),
      weekday = integer(),
      slot_type = character(),
      polarity = character(),
      hard = logical()
    ))
  }
  p$operator_id <- trimws(as.character(p$operator_id))
  p$weekday <- suppressWarnings(as.integer(p$weekday))
  p$slot_type <- as.character(p$slot_type)
  p$polarity <- as.character(p$polarity)
  if (is.null(p$hard)) p$hard <- FALSE
  p$hard <- as.logical(p$hard)
  tibble::as_tibble(p)
}

.read_month <- function(path) {
  m <- readxl::read_excel(path, sheet = "month")
  m$month <- as.character(m$month)
  tibble::as_tibble(m)
}
