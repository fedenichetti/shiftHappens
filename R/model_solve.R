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
  obj <- if (status %in% feasible_states) {
    tryCatch(ompr::objective_value(sol), error = function(e) NA_real_)
  } else NA_real_
  solution_df <- if (status %in% feasible_states) {
    df <- ompr::get_solution(sol, x[op, day, slot, role_pos])
    df <- df[df$value > 0.5, c("op", "day", "slot", "role_pos")]
    tibble::as_tibble(df)
  } else NULL

  list(
    status = status,
    runtime_seconds = runtime,
    objective_value = obj,
    solution = solution_df
  )
}
