test_that("solve_milp returns optimal/success status for trivial input", {
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
  expect_true(res$status %in% c("optimal", "success", "feasible"))
  expect_s3_class(res$solution, "tbl_df")
  expect_named(res$solution, c("op", "day", "slot", "role_pos"))
})

test_that("solve_milp returns infeasible status when infeasible", {
  # 0 seniors over 1 day -> coverage of role 1 is impossible.
  ops <- tibble::tibble(
    surname = c("J1","J2"),
    name = "",
    role = c("nurse_2","nurse_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date("2026-06-01"),
    weekday = 1L, is_weekend = FALSE, is_holiday = FALSE,
    slot_kind = "weekday",
    slots = list(slots_for_kind("weekday"))
  )
  rules <- load_rules(testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml"))
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(2)),
    calendar = dplyr::mutate(cal, day_idx = 1L),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:2, operator_id = ops$surname, carry_count = 0L),
    preferences = NULL
  )
  m <- build_milp(ctx)
  res <- solve_milp(m, time_limit_seconds = 30L)
  expect_true(res$status %in% c("infeasible", "no solution", "error"))
})

test_that("diagnose_infeasibility identifies senior cap as the cause", {
  # 2 seniors + 3 weekdays + senior_max = 1 -> infeasible because
  # 2 seniors can cover only 2 days (one each), but 3 days need coverage.
  # Relaxing H9 (senior cap) makes it feasible: with weekday rest the
  # two seniors can alternate over 3 days (s1: d1,d3; s2: d2).
  ops <- tibble::tibble(
    surname = c("S1","S2","J1","J2"),
    name = "",
    role = c("senior","senior","nurse_2","nurse_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-01","2026-06-03","2026-06-05")),
    weekday = c(1L,3L,5L), is_weekend = FALSE, is_holiday = FALSE,
    slot_kind = "weekday",
    slots = rep(list(slots_for_kind("weekday")), 3)
  )
  rules <- load_rules(testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml"))
  rules$limits$senior_max_per_month <- 1L
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(4)),
    calendar = dplyr::mutate(cal, day_idx = seq_len(3)),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:4, operator_id = ops$surname, carry_count = 0L),
    preferences = NULL
  )
  diag <- diagnose_infeasibility(ctx)
  expect_equal(diag$cause, "senior_cap")
  expect_match(diag$suggestion, "senior_max_per_month")
})
