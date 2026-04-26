#' Build the deterministic context the MILP needs:
#'   - operators: tibble with op_idx (1..N), operator_id, role
#'   - calendar:  tibble with day_idx (1..D), date, slot_kind, ... slots
#'   - rules:     pass-through rules list
#'   - absent_idx: matrix of (op_idx, day_idx) pairs the operator can't cover
#'   - carry_in:  per-operator counts from history within rolling window
#'
#' This is plain data transformation -- no ompr involvement yet.
#'
#' @param wb result of read_workbook
#' @param rules result of load_rules
#' @param cal  result of build_calendar (for the target month)
#' @return list
build_model_context <- function(wb, rules, cal) {
  ops <- wb$operators
  ops$operator_id <- ifelse(
    is.na(ops$name) | ops$name == "",
    ops$surname,
    paste(ops$surname, ops$name, sep = "_")
  )
  # collapse duplicates after id construction
  ops <- dplyr::distinct(ops, operator_id, .keep_all = TRUE)
  ops$op_idx <- seq_len(nrow(ops))

  cal$day_idx <- seq_len(nrow(cal))

  # Absence (op_idx, day_idx) pairs
  absent <- matrix(integer(0), ncol = 2)
  if (!is.null(wb$absences) && nrow(wb$absences) > 0) {
    for (i in seq_len(nrow(wb$absences))) {
      a <- wb$absences[i, ]
      op_match <- ops$op_idx[ops$operator_id == a$operator_id |
                               ops$surname == a$operator_id]
      if (length(op_match) == 0) next
      days <- seq(a$date_from, a$date_to, by = "day")
      day_match <- cal$day_idx[cal$date %in% days]
      if (length(day_match) == 0) next
      pairs <- expand.grid(op = op_match, day = day_match)
      absent <- rbind(absent, as.matrix(pairs))
    }
  }

  # carry_in counts from history in rolling window
  win_months <- rules$limits$rolling_history_months
  target_start <- as.Date(sprintf(
    "%04d-%02d-01",
    lubridate::year(cal$date[1]),
    lubridate::month(cal$date[1])
  ))
  win_start <- target_start - months(win_months)
  hist <- if (!is.null(wb$history) && nrow(wb$history) > 0) {
    wb$history[wb$history$date >= win_start &
                 wb$history$date < target_start, ]
  } else {
    wb$history
  }
  carry <- if (!is.null(hist) && nrow(hist) > 0) {
    dplyr::count(hist, operator_id, name = "carry_count")
  } else {
    tibble::tibble(operator_id = character(0), carry_count = integer(0))
  }
  carry_full <- ops |>
    dplyr::select("op_idx", "operator_id") |>
    dplyr::left_join(carry, by = "operator_id") |>
    dplyr::mutate(carry_count = tidyr::replace_na(.data$carry_count, 0L))

  list(
    operators  = ops,
    calendar   = cal,
    rules      = rules,
    absent_idx = absent,
    carry_in   = carry_full
  )
}
