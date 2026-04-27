test_that("postprocess produces schedule and summary tibbles", {
  ops <- tibble::tibble(
    surname = c("S1","S2","S3","J1","J2","J3"),
    name = "",
    role = c("senior","senior","senior","nurse_2","nurse_2","nurse_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-01","2026-06-02","2026-06-03")),
    weekday = c(1L,2L,3L), is_weekend = FALSE, is_holiday = FALSE,
    slot_kind = "weekday",
    slots = list(slots_for_kind("weekday"), slots_for_kind("weekday"),
                 slots_for_kind("weekday"))
  )
  rules <- load_rules(testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml"))
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(6)),
    calendar = dplyr::mutate(cal, day_idx = seq_len(3)),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:6, operator_id = ops$surname, carry_count = 0L),
    preferences = NULL
  )
  m <- build_milp(ctx)
  res <- solve_milp(m, time_limit_seconds = 30L)
  out <- postprocess_solution(res, ctx)

  expect_named(out, c("schedule", "summary", "diagnostics"))
  expect_s3_class(out$schedule, "tbl_df")
  expect_named(out$schedule, c("date", "weekday", "1° reperibile", "2° reperibile"))
  expect_equal(nrow(out$schedule), 3L)
  expect_equal(out$schedule$weekday, c("L","M","M"))   # Mon, Tue, Wed in IT

  expect_s3_class(out$summary, "tbl_df")
  expect_named(out$summary,
    c("operator_id", "role",
      "n_first", "n_second", "n_weekend", "n_holiday",
      "total", "carry_in_window", "delta_vs_mean"))
  expect_equal(sum(out$summary$total), 6L)   # 3 days * 2 roles
})

test_that("postprocess formats weekend cells as 'X / Y'", {
  ops <- tibble::tibble(
    surname = c("S1","S2","J1","J2"),
    name = "",
    role = c("senior","senior","nurse_2","nurse_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date("2026-06-06"),  # Sat
    weekday = 6L, is_weekend = TRUE, is_holiday = FALSE,
    slot_kind = "weekend",
    slots = list(slots_for_kind("weekend"))
  )
  rules <- load_rules(testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml"))
  rules$limits$min_free_weekends_per_month <- 0L  # only 1 weekend in fixture
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(4)),
    calendar = dplyr::mutate(cal, day_idx = 1L),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:4, operator_id = ops$surname, carry_count = 0L),
    preferences = NULL
  )
  m <- build_milp(ctx)
  res <- solve_milp(m, time_limit_seconds = 30L)
  out <- postprocess_solution(res, ctx)
  expect_match(out$schedule$`1° reperibile`[1], "/")
  expect_match(out$schedule$`2° reperibile`[1], "/")
})

test_that("postprocess returns NULL schedule when solve was not feasible", {
  fake_result <- list(
    status = "infeasible",
    runtime_seconds = 0.5,
    objective_value = NA_real_,
    solution = NULL
  )
  ctx <- list(
    operators = tibble::tibble(op_idx = 1:2, operator_id = c("X","Y"), role = c("senior","nurse_2")),
    calendar = tibble::tibble(day_idx = 1L, date = as.Date("2026-06-01"),
                              weekday = 1L, is_weekend = FALSE, is_holiday = FALSE,
                              slot_kind = "weekday", slots = list(slots_for_kind("weekday"))),
    rules = list(),
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:2, operator_id = c("X","Y"), carry_count = 0L),
    preferences = NULL
  )
  out <- postprocess_solution(fake_result, ctx)
  expect_null(out$schedule)
  expect_null(out$summary)
  expect_s3_class(out$diagnostics, "tbl_df")
  expect_true("solver_status" %in% out$diagnostics$field)
})
