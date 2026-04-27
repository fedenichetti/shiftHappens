.weekday_letter_it <- c("L","M","M","G","V","S","D")

#' Convert a solver result + model context into the three output tibbles
#' that go into the .xlsx download.
#'
#' @param solve_result list returned by solve_milp
#' @param ctx model context (from build_model_context)
#' @return list(schedule, summary, diagnostics)
#' @export
postprocess_solution <- function(solve_result, ctx) {
  feasible <- solve_result$status %in% c("optimal", "success", "feasible")

  if (!feasible || is.null(solve_result$solution)) {
    return(list(
      schedule = NULL,
      summary = NULL,
      diagnostics = .build_diagnostics(solve_result, ctx, NULL)
    ))
  }

  sol <- solve_result$solution
  ops <- ctx$operators
  cal <- ctx$calendar

  # Join op metadata onto each assignment.
  sol <- dplyr::left_join(sol, ops[, c("op_idx", "operator_id")],
                          by = c("op" = "op_idx"))

  # Resolve each (day, slot) to its (role, period).
  slot_lookup <- purrr::map_dfr(seq_len(nrow(cal)), function(d) {
    s <- cal$slots[[d]]
    s$day <- d
    s$slot <- seq_len(nrow(s))
    s
  })
  sol <- dplyr::left_join(sol, slot_lookup, by = c("day", "slot"))
  sol <- dplyr::left_join(sol,
    cal[, c("day_idx", "date", "is_weekend", "is_holiday", "slot_kind")],
    by = c("day" = "day_idx"))

  # Schedule: one row per date.
  fmt_cell <- function(rows) {
    if (nrow(rows) == 0) return("")
    if (nrow(rows) == 1) return(rows$operator_id[1])
    # weekend/holiday: day name "/" night name
    day_op   <- rows$operator_id[rows$period == "day"]
    night_op <- rows$operator_id[rows$period == "night"]
    paste(
      paste(day_op,   collapse = "+"),
      paste(night_op, collapse = "+"),
      sep = " / "
    )
  }

  schedule <- purrr::map_dfr(seq_len(nrow(cal)), function(d) {
    day_sol <- sol[sol$day == d, ]
    first  <- day_sol[day_sol$role_pos == 1L, ]
    second <- day_sol[day_sol$role_pos == 2L, ]
    tibble::tibble(
      date = cal$date[d],
      weekday = .weekday_letter_it[cal$weekday[d]],
      `1° reperibile` = fmt_cell(first),
      `2° reperibile` = fmt_cell(second)
    )
  })

  # Per-operator summary.
  count_by <- function(predicate) {
    s_filtered <- sol[predicate, ]
    counts <- dplyr::count(s_filtered, op, name = "n")
    out_n <- dplyr::left_join(
      ops[, c("op_idx", "operator_id")],
      counts,
      by = c("op_idx" = "op")
    )$n
    ifelse(is.na(out_n), 0L, out_n)
  }

  n_first   <- count_by(sol$role_pos == 1L)
  n_second  <- count_by(sol$role_pos == 2L)
  n_weekend <- count_by(sol$is_weekend & !sol$is_holiday)
  n_holiday <- count_by(sol$is_holiday)
  total     <- n_first + n_second
  carry     <- ctx$carry_in$carry_count[match(ops$op_idx, ctx$carry_in$op_idx)]
  carry     <- ifelse(is.na(carry), 0L, carry)

  # delta_vs_mean: per role group, (total + carry) - group mean of same.
  delta <- numeric(nrow(ops))
  for (g in unique(ops$role)) {
    idx <- ops$role == g
    grp_total <- total[idx] + carry[idx]
    delta[idx] <- (total[idx] + carry[idx]) - mean(grp_total)
  }

  summary_df <- tibble::tibble(
    operator_id     = ops$operator_id,
    role            = ops$role,
    n_first         = as.integer(n_first),
    n_second        = as.integer(n_second),
    n_weekend       = as.integer(n_weekend),
    n_holiday       = as.integer(n_holiday),
    total           = as.integer(total),
    carry_in_window = as.integer(carry),
    delta_vs_mean   = round(delta, 2)
  )

  list(
    schedule    = schedule,
    summary     = summary_df,
    diagnostics = .build_diagnostics(solve_result, ctx, sol)
  )
}

#' Build the diagnostics tibble shown to the user.
#'
#' @param solve_result list from solve_milp
#' @param ctx model context (unused for now; reserved for relaxation reporting)
#' @param sol joined solution tibble (or NULL if not feasible)
#' @return tibble (field, value)
#' @noRd
.build_diagnostics <- function(solve_result, ctx, sol) {
  tibble::tibble(
    field = c("solver_status", "runtime_seconds", "objective_value"),
    value = c(
      solve_result$status %||% "unknown",
      sprintf("%.2f", solve_result$runtime_seconds %||% NA_real_),
      ifelse(is.na(solve_result$objective_value %||% NA_real_),
             "-", sprintf("%.2f", solve_result$objective_value))
    )
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a
