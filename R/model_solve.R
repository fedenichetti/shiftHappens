#' Solve an ompr MIPModel and return a friendly status + solution tibble.
#'
#' @param model ompr model
#' @param time_limit_seconds numeric; passed as tm_limit (in milliseconds)
#'        to the GLPK solver
#' @return list:
#'   status           "optimal" / "success" / "feasible" / "infeasible" /
#'                    "no solution" / "timeout" / "error"
#'   runtime_seconds  numeric
#'   objective_value  numeric (NA if not solved)
#'   solution         tibble(op, day, slot, role_pos) of x == 1 rows,
#'                    or NULL if not solved
solve_milp <- function(model, time_limit_seconds = 30L) {
  t0 <- Sys.time()
  tm_ms <- as.integer(time_limit_seconds * 1000L)
  sol <- tryCatch(
    ompr::solve_model(model,
      ompr.roi::with_ROI(
        solver = "glpk",
        verbose = FALSE,
        control = list(tm_limit = tm_ms)
      )
    ),
    error = function(e) e
  )
  runtime <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (inherits(sol, "error")) {
    return(list(
      status = "error",
      runtime_seconds = runtime,
      objective_value = NA_real_,
      solution = NULL,
      error_message = conditionMessage(sol)
    ))
  }

  status <- ompr::solver_status(sol)
  feasible_states <- c("optimal", "success", "feasible")
  infeasible_states <- c("infeasible", "no solution")

  if (status %in% feasible_states) {
    obj <- tryCatch(ompr::objective_value(sol), error = function(e) NA_real_)
    df <- ompr::get_solution(sol, x[op, day, slot, role_pos])
    df <- df[df$value > 0.5, c("op", "day", "slot", "role_pos")]
    return(list(
      status = status,
      runtime_seconds = runtime,
      objective_value = obj,
      solution = tibble::as_tibble(df)
    ))
  }

  # Detect timeout: either the solver returned a time-related status string,
  # or runtime ran up against the configured time_limit_seconds and we did
  # not get an explicit infeasibility proof.
  timeout_hit <-
    grepl("time", tolower(status %||% "")) ||
    (runtime >= time_limit_seconds * 0.95 && !(status %in% infeasible_states))

  if (timeout_hit) {
    return(list(
      status = "timeout",
      runtime_seconds = runtime,
      objective_value = NA_real_,
      solution = NULL,
      error_message = "Solver took too long. Consider reducing fairness weights or removing edge-case absences."
    ))
  }

  list(
    status = status,
    runtime_seconds = runtime,
    objective_value = NA_real_,
    solution = NULL
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

#' Diagnose why a model is infeasible by removing relaxable hard
#' constraints one at a time.
#'
#' Tries (in order):
#'   1. drop H8 (free weekend rule) -> "weekend_cap"
#'   2. drop H9 (senior cap)         -> "senior_cap"
#'   3. drop H10 (hard preferences)  -> "hard_preferences"
#'   4. all of the above             -> "absences" (i.e., absences alone
#'                                       make it infeasible — review them)
#'
#' Returns: list(cause = chr, suggestion = chr).
#'
#' @param ctx model context
#' @return list
diagnose_infeasibility <- function(ctx) {
  relax <- function(modified_ctx) {
    m <- build_milp(modified_ctx)
    res <- solve_milp(m, time_limit_seconds = ctx$rules$solver$time_limit_seconds)
    res$status %in% c("optimal", "success", "feasible")
  }

  # 1. Relax H8 (free weekends)
  ctx_no_h8 <- ctx
  ctx_no_h8$rules$limits$min_free_weekends_per_month <- 0L
  if (relax(ctx_no_h8)) {
    return(list(
      cause = "weekend_cap",
      suggestion = paste(
        "Cannot achieve",
        ctx$rules$limits$min_free_weekends_per_month,
        "free weekends per operator. Consider lowering",
        "min_free_weekends_per_month in the rules YAML or removing",
        "absences that block weekend coverage."
      )
    ))
  }

  # 2. Relax H9 (senior cap)
  ctx_no_h9 <- ctx
  ctx_no_h9$rules$limits$senior_max_per_month <- 999L
  if (relax(ctx_no_h9)) {
    return(list(
      cause = "senior_cap",
      suggestion = paste(
        "Senior monthly cap of", ctx$rules$limits$senior_max_per_month,
        "is too low for the number of days needing coverage. Raise",
        "senior_max_per_month in the rules YAML."
      )
    ))
  }

  # 3. Relax H10 (hard preferences -> all soft)
  ctx_no_h10 <- ctx
  if (!is.null(ctx_no_h10$preferences) && nrow(ctx_no_h10$preferences) > 0) {
    ctx_no_h10$preferences$hard <- FALSE
  }
  if (relax(ctx_no_h10)) {
    return(list(
      cause = "hard_preferences",
      suggestion = paste(
        "Hard preferences make the schedule infeasible.",
        "Demote one or more preference rows from hard=TRUE to hard=FALSE."
      )
    ))
  }

  # 4. All relaxed but still infeasible -> absences / structural
  ctx_all <- ctx_no_h8
  ctx_all$rules$limits$senior_max_per_month <- 999L
  if (!is.null(ctx_all$preferences) && nrow(ctx_all$preferences) > 0) {
    ctx_all$preferences$hard <- FALSE
  }
  if (relax(ctx_all)) {
    return(list(
      cause = "combined",
      suggestion = paste(
        "Combination of weekend cap, senior cap, and hard preferences.",
        "Adjust two or more knobs (free weekends, senior cap, demote hard prefs)."
      )
    ))
  }

  list(
    cause = "absences",
    suggestion = paste(
      "Even with all soft rules relaxed the schedule is infeasible.",
      "Review absences for over-coverage of any single day (too many",
      "operators unavailable on the same date), or check that the",
      "operator pool is large enough for the month."
    )
  )
}
