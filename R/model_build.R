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

#' Build the MILP for an on-call month using the prepared context.
#'
#' Decision variable: x[op, day, slot, role_pos] in {0,1} where slot is
#' the index within calendar$slots[[day]] and role_pos in {1,2} for
#' (first, second).
#'
#' This task adds H1 (coverage) only. Subsequent tasks layer on H2-H10.
#'
#' @param ctx result of build_model_context
#' @return ompr optimization_model
build_milp <- function(ctx) {
  N_op  <- nrow(ctx$operators)
  N_day <- nrow(ctx$calendar)
  # Maximum slots-per-day across the month (for tensor sizing).
  max_slots <- max(purrr::map_int(ctx$calendar$slots, nrow))
  # Build a tibble of valid (day_idx, slot_idx, role) triples.
  slot_grid <- purrr::map_dfr(seq_len(N_day), function(d) {
    s <- ctx$calendar$slots[[d]]
    s$day_idx  <- d
    s$slot_idx <- seq_len(nrow(s))
    s
  })

  m <- ompr::MIPModel()
  m <- ompr::add_variable(
    m,
    x[op, day, slot, role_pos],
    op       = 1:N_op,
    day      = 1:N_day,
    slot     = 1:max_slots,
    role_pos = 1:2,
    type     = "binary"
  )

  # H1 coverage: for every (day, slot, role_pos) tuple that exists in
  # slot_grid, exactly one operator is assigned. role_pos 1 = "first",
  # 2 = "second"; map slot_grid$role to role_pos here.
  for (i in seq_len(nrow(slot_grid))) {
    d  <- slot_grid$day_idx[i]
    s  <- slot_grid$slot_idx[i]
    rp <- if (slot_grid$role[i] == "first") 1L else 2L
    m <- ompr::add_constraint(m, ompr::sum_over(x[op, d, s, rp], op = 1:N_op) == 1)
  }

  # Hidden tuples (slot_idx beyond what this day actually has): force to 0.
  for (d in seq_len(N_day)) {
    actual_slots <- nrow(ctx$calendar$slots[[d]])
    if (actual_slots < max_slots) {
      for (s in (actual_slots + 1L):max_slots) {
        for (rp in 1:2) {
          m <- ompr::add_constraint(m, ompr::sum_over(x[op, d, s, rp], op = 1:N_op) == 0)
        }
      }
    }
  }

  # H2: only seniors take role_pos = 1 (first)
  senior_idx <- ctx$operators$op_idx[ctx$operators$role == "senior"]
  junior_idx <- setdiff(seq_len(N_op), senior_idx)
  for (op_j in junior_idx) {
    m <- ompr::add_constraint(m,
      ompr::sum_over(x[op_j, d, s, 1], d = 1:N_day, s = 1:max_slots) == 0
    )
  }
  # H3: any operator may take role_pos = 2 -- no extra constraint needed,
  # variables already exist for all ops.

  # H4: absent (op, day) pairs are zeroed across all slots/roles.
  if (nrow(ctx$absent_idx) > 0) {
    for (i in seq_len(nrow(ctx$absent_idx))) {
      op_a  <- ctx$absent_idx[i, 1]
      day_a <- ctx$absent_idx[i, 2]
      m <- ompr::add_constraint(m,
        ompr::sum_over(x[op_a, day_a, s, rp], s = 1:max_slots, rp = 1:2) == 0
      )
    }
  }

  m
}
