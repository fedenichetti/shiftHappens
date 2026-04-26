test_that("build_model_context returns deterministic indices", {
  fixture <- testthat::test_path("..", "..", "inst", "examples", "may2026_workbook.xlsx")
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  wb <- read_workbook(fixture)
  rules <- load_rules(rules_path)
  cal <- build_calendar(2026, 6, holidays_extra = rules$holidays_extra)
  ctx <- build_model_context(wb, rules, cal)

  expect_setequal(names(ctx),
    c("operators", "calendar", "rules", "absent_idx", "carry_in"))
  expect_s3_class(ctx$operators, "tbl_df")
  expect_true("op_idx" %in% names(ctx$operators))
  expect_true(all(ctx$operators$op_idx == seq_len(nrow(ctx$operators))))
  expect_s3_class(ctx$calendar, "tbl_df")
  expect_true("day_idx" %in% names(ctx$calendar))
})

test_that("build_model_context flags absent (op, day) pairs", {
  fixture <- testthat::test_path("..", "..", "inst", "examples", "may2026_workbook.xlsx")
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  wb <- read_workbook(fixture)
  wb$absences <- tibble::tibble(
    operator_id = "Carniti",
    date_from   = as.Date("2026-06-05"),
    date_to     = as.Date("2026-06-07"),
    type        = "vacation"
  )
  rules <- load_rules(rules_path)
  cal <- build_calendar(2026, 6, holidays_extra = list())
  ctx <- build_model_context(wb, rules, cal)
  carniti_idx <- ctx$operators$op_idx[ctx$operators$operator_id == "Carniti" |
                                        ctx$operators$surname == "Carniti"]
  june5_idx   <- ctx$calendar$day_idx[ctx$calendar$date == as.Date("2026-06-05")]
  expect_true(any(ctx$absent_idx[, 1] == carniti_idx[1] &
                  ctx$absent_idx[, 2] == june5_idx))
})

test_that("build_milp produces an ompr model object", {
  fixture <- testthat::test_path("..", "..", "inst", "examples", "may2026_workbook.xlsx")
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  wb <- read_workbook(fixture)
  rules <- load_rules(rules_path)
  cal <- build_calendar(2026, 6, holidays_extra = list())
  ctx <- build_model_context(wb, rules, cal)
  m <- build_milp(ctx)
  expect_true(inherits(m, "optimization_model") ||
              inherits(m, "linear_optimization_model") ||
              inherits(m, "abstract_model"))
  expect_gt(ompr::nvars(m)$binary, 0L)
})

test_that("solver returns a feasible assignment for trivial input", {
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  ops <- tibble::tibble(
    surname = c("S1", "S2", "S3", "J1", "J2", "J3"),
    name = "",
    role = c("senior", "senior", "senior", "nurse_2", "nurse_2", "nurse_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-01", "2026-06-02", "2026-06-03")),
    weekday = c(1L, 2L, 3L),
    is_weekend = FALSE,
    is_holiday = FALSE,
    slot_kind = "weekday",
    slots = list(
      slots_for_kind("weekday"),
      slots_for_kind("weekday"),
      slots_for_kind("weekday")
    )
  )
  rules <- load_rules(rules_path)
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(6)),
    calendar = dplyr::mutate(cal, day_idx = seq_len(3)),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:6, operator_id = ops$surname, carry_count = 0L)
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
})
