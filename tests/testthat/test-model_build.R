test_that("build_model_context returns deterministic indices", {
  fixture <- testthat::test_path("..", "..", "inst", "examples", "may2026_workbook.xlsx")
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  wb <- read_workbook(fixture)
  rules <- load_rules(rules_path)
  cal <- build_calendar(2026, 6, holidays_extra = rules$holidays_extra)
  ctx <- build_model_context(wb, rules, cal)

  expect_setequal(names(ctx),
    c("operators", "calendar", "rules", "absent_idx", "carry_in", "preferences"))
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

test_that("only seniors can be assigned to first role", {
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  ops <- tibble::tibble(
    surname = c("S1", "S2", "J1", "J2", "J3"),
    name = "",
    role = c("senior", "senior", "nurse_2", "oss_2", "oss_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-01", "2026-06-02")),
    weekday = c(1L, 2L),
    is_weekend = FALSE,
    is_holiday = FALSE,
    slot_kind = "weekday",
    slots = list(slots_for_kind("weekday"), slots_for_kind("weekday"))
  )
  rules <- load_rules(rules_path)
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(nrow(ops))),
    calendar = dplyr::mutate(cal, day_idx = seq_len(nrow(cal))),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = seq_len(nrow(ops)), operator_id = ops$surname, carry_count = 0L)
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
  vals <- ompr::get_solution(sol, x[op, day, slot, role_pos])
  vals <- vals[vals$value > 0.5, ]
  # Only seniors (op_idx 1, 2) ever fill role_pos == 1.
  expect_true(all(vals$op[vals$role_pos == 1L] %in% c(1L, 2L)))
})

test_that("absent operator is never assigned", {
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  ops <- tibble::tibble(
    surname = c("S1", "S2", "J1", "J2"),
    name = "",
    role = c("senior", "senior", "nurse_2", "nurse_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-01", "2026-06-02")),
    weekday = c(1L, 2L),
    is_weekend = FALSE,
    is_holiday = FALSE,
    slot_kind = "weekday",
    slots = list(slots_for_kind("weekday"), slots_for_kind("weekday"))
  )
  rules <- load_rules(rules_path)
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(nrow(ops))),
    calendar = dplyr::mutate(cal, day_idx = seq_len(nrow(cal))),
    rules = rules,
    absent_idx = matrix(c(1L, 1L), ncol = 2, byrow = TRUE),  # S1 absent on day 1
    carry_in = tibble::tibble(op_idx = 1:4, operator_id = ops$surname, carry_count = 0L)
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
  vals <- ompr::get_solution(sol, x[op, day, slot, role_pos])
  vals <- vals[vals$value > 0.5, ]
  expect_false(any(vals$op == 1L & vals$day == 1L))
})

test_that("H5 forbids same operator on two consecutive weekdays", {
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  ops <- tibble::tibble(
    surname = c("S1", "S2", "J1", "J2"),
    name = "",
    role = c("senior", "senior", "nurse_2", "nurse_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-01", "2026-06-02", "2026-06-03", "2026-06-04")),
    weekday = 1:4,
    is_weekend = FALSE,
    is_holiday = FALSE,
    slot_kind = "weekday",
    slots = list(slots_for_kind("weekday"), slots_for_kind("weekday"),
                 slots_for_kind("weekday"), slots_for_kind("weekday"))
  )
  rules <- load_rules(rules_path)
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(4)),
    calendar = dplyr::mutate(cal, day_idx = seq_len(4)),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:4, operator_id = ops$surname, carry_count = 0L)
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
  vals <- ompr::get_solution(sol, x[op, day, slot, role_pos])
  vals <- vals[vals$value > 0.5, ]
  for (op_i in 1:4) {
    op_days <- sort(unique(vals$day[vals$op == op_i]))
    if (length(op_days) >= 2) {
      expect_true(min(diff(op_days)) >= 2L,
                  info = paste("op", op_i, "has consecutive days"))
    }
  }
})

test_that("H7 forbids the three banned weekend combinations", {
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  ops <- tibble::tibble(
    surname = c("S1", "S2", "J1", "J2"),
    name = "",
    role = c("senior", "senior", "nurse_2", "nurse_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-06", "2026-06-07")),  # Sat, Sun
    weekday = c(6L, 7L),
    is_weekend = TRUE,
    is_holiday = FALSE,
    slot_kind = "weekend",
    slots = list(slots_for_kind("weekend"), slots_for_kind("weekend"))
  )
  rules <- load_rules(rules_path)
  rules$limits$min_free_weekends_per_month <- 0L  # only 1 weekend in fixture
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(4)),
    calendar = dplyr::mutate(cal, day_idx = seq_len(2)),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:4, operator_id = ops$surname, carry_count = 0L)
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
  vals <- ompr::get_solution(sol, x[op, day, slot, role_pos])
  vals <- vals[vals$value > 0.5, ]
  # Slot indices for weekend day-of-week template:
  #   1 = first/day, 2 = first/night, 3 = second/day, 4 = second/night
  for (op_i in 1:4) {
    sat_d <- any(vals$op == op_i & vals$day == 1 & vals$slot %in% c(1, 3))
    sat_n <- any(vals$op == op_i & vals$day == 1 & vals$slot %in% c(2, 4))
    sun_d <- any(vals$op == op_i & vals$day == 2 & vals$slot %in% c(1, 3))
    sun_n <- any(vals$op == op_i & vals$day == 2 & vals$slot %in% c(2, 4))
    expect_false(sat_d && sat_n)
    expect_false(sat_n && sun_d)
    expect_false(sun_d && sun_n)
  }
})

test_that("H8 enforces min_free_weekends_per_month", {
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  # Pool sized so the cap (1 worked weekend / op) is easy to satisfy:
  # 2 weekends * 4 senior-first slots = 8 senior covers; with H7 each op
  # covers ~2 weekend slots; 4+ seniors suffice. Zero out the fairness
  # weights so the solver doesn't have to prove dispersion-optimality
  # (constraint correctness is what the test asserts).
  ops <- tibble::tibble(
    surname = c("S1", "S2", "S3", "S4", "S5", "S6",
                "J1", "J2", "J3", "J4", "J5", "J6"),
    name = "",
    role = c(rep("senior", 6), rep("nurse_2", 6)),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  # Days: Sat 6, Sun 7, Mon 8, Sat 13, Sun 14
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-06", "2026-06-07", "2026-06-08",
                     "2026-06-13", "2026-06-14")),
    weekday = c(6L, 7L, 1L, 6L, 7L),
    is_weekend = c(TRUE, TRUE, FALSE, TRUE, TRUE),
    is_holiday = FALSE,
    slot_kind = c("weekend", "weekend", "weekday", "weekend", "weekend"),
    slots = list(slots_for_kind("weekend"), slots_for_kind("weekend"),
                 slots_for_kind("weekday"), slots_for_kind("weekend"),
                 slots_for_kind("weekend"))
  )
  rules <- load_rules(rules_path)
  rules$limits$min_free_weekends_per_month <- 1L
  rules$fairness_weights$monthly_total <- 0
  rules$fairness_weights$weekend_holiday <- 0
  rules$fairness_weights$preference <- 0
  N <- nrow(ops)
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(N)),
    calendar = dplyr::mutate(cal, day_idx = seq_len(5)),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = seq_len(N), operator_id = ops$surname, carry_count = 0L),
    preferences = NULL
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
  vals <- ompr::get_solution(sol, x[op, day, slot, role_pos])
  vals <- vals[vals$value > 0.5, ]
  for (op_i in seq_len(N)) {
    op_dates <- ctx$calendar$date[ctx$calendar$day_idx %in% vals$day[vals$op == op_i] &
                                     ctx$calendar$is_weekend]
    weekends_grouped <- length(unique(format(op_dates, "%G-W%V")))
    expect_lte(weekends_grouped, 1L)
  }
})

test_that("H10 hard preference excludes operator from matching slot", {
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
    date = as.Date("2026-06-01"),
    weekday = 1L, is_weekend = FALSE, is_holiday = FALSE,
    slot_kind = "weekday",
    slots = list(slots_for_kind("weekday"))
  )
  rules <- load_rules(rules_path)
  prefs <- tibble::tibble(
    operator_id = "S1",
    weekday = 1L,
    slot_type = NA_character_,
    polarity = "avoid",
    hard = TRUE
  )
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(6)),
    calendar = dplyr::mutate(cal, day_idx = 1L),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:6, operator_id = ops$surname, carry_count = 0L),
    preferences = prefs
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
  vals <- ompr::get_solution(sol, x[op, day, slot, role_pos])
  vals <- vals[vals$value > 0.5, ]
  expect_false(any(vals$op == 1L))
})

test_that("soft objective minimizes senior dispersion", {
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  ops <- tibble::tibble(
    surname = c("S1", "S2", "S3", "S4", "J1", "J2", "J3", "J4"),
    name = "",
    role = c(rep("senior", 4), rep("nurse_2", 4)),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  # 8 well-spaced weekdays so 8 first-role slots are needed; gaps avoid H5.
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-01", "2026-06-03", "2026-06-05", "2026-06-08",
                     "2026-06-10", "2026-06-12", "2026-06-15", "2026-06-17")),
    weekday = c(1L, 3L, 5L, 1L, 3L, 5L, 1L, 3L),
    is_weekend = FALSE, is_holiday = FALSE,
    slot_kind = "weekday",
    slots = list(slots_for_kind("weekday"), slots_for_kind("weekday"),
                 slots_for_kind("weekday"), slots_for_kind("weekday"),
                 slots_for_kind("weekday"), slots_for_kind("weekday"),
                 slots_for_kind("weekday"), slots_for_kind("weekday"))
  )
  rules <- load_rules(rules_path)
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(8)),
    calendar = dplyr::mutate(cal, day_idx = seq_len(8)),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:8, operator_id = ops$surname, carry_count = 0L),
    preferences = NULL
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
  vals <- ompr::get_solution(sol, x[op, day, slot, role_pos])
  vals <- vals[vals$value > 0.5, ]
  senior_counts <- sapply(1:4, function(op) sum(vals$op == op & vals$role_pos == 1L))
  expect_equal(max(senior_counts) - min(senior_counts), 0L)
})

test_that("H6 forbids weekend-then-Monday for the same operator", {
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  # Use a roomier pool so the model has at least one senior free from Sunday
  # to cover Monday's first-role slot (otherwise H6 leaves no senior).
  ops <- tibble::tibble(
    surname = c("S1", "S2", "S3", "S4", "J1", "J2", "J3", "J4"),
    name = "",
    role = c(rep("senior", 4), rep("nurse_2", 4)),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-06", "2026-06-07", "2026-06-08")),  # Sat, Sun, Mon
    weekday = c(6L, 7L, 1L),
    is_weekend = c(TRUE, TRUE, FALSE),
    is_holiday = FALSE,
    slot_kind = c("weekend", "weekend", "weekday"),
    slots = list(slots_for_kind("weekend"), slots_for_kind("weekend"),
                 slots_for_kind("weekday"))
  )
  rules <- load_rules(rules_path)
  rules$limits$min_free_weekends_per_month <- 0L  # only 1 weekend, can't enforce 2 free
  N <- nrow(ops)
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(N)),
    calendar = dplyr::mutate(cal, day_idx = seq_len(3)),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = seq_len(N), operator_id = ops$surname, carry_count = 0L),
    preferences = NULL
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
  vals <- ompr::get_solution(sol, x[op, day, slot, role_pos])
  vals <- vals[vals$value > 0.5, ]
  for (op_i in seq_len(N)) {
    sun_assignments <- any(vals$op == op_i & vals$day == 2)
    mon_assignments <- any(vals$op == op_i & vals$day == 3)
    expect_false(sun_assignments && mon_assignments,
                 info = paste("op", op_i, "covers both Sunday and Monday"))
  }
})

test_that("H9 caps each senior at senior_max_per_month role-first slots", {
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  # 2 seniors over 4 weekdays. Cap = 2 each. With 4 first-role slots needed,
  # the only feasible split is exactly 2 each.
  ops <- tibble::tibble(
    surname = c("S1", "S2", "J1", "J2"),
    name = "",
    role = c("senior", "senior", "nurse_2", "nurse_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-01", "2026-06-03", "2026-06-05", "2026-06-08")),
    weekday = c(1L, 3L, 5L, 1L), is_weekend = FALSE, is_holiday = FALSE,
    slot_kind = "weekday",
    slots = rep(list(slots_for_kind("weekday")), 4)
  )
  rules <- load_rules(rules_path)
  rules$limits$senior_max_per_month <- 2L
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(4)),
    calendar = dplyr::mutate(cal, day_idx = seq_len(4)),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:4, operator_id = ops$surname, carry_count = 0L),
    preferences = NULL
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
  vals <- ompr::get_solution(sol, x[op, day, slot, role_pos])
  vals <- vals[vals$value > 0.5, ]
  for (op_i in 1:2) {  # both seniors
    n_first <- sum(vals$op == op_i & vals$role_pos == 1L)
    expect_lte(n_first, 2L)
  }
})

test_that("Tier 2 weekend equity factors in carry-in counts", {
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  # 2 seniors + 2 juniors over 1 weekend. S1 carries 2 prior weekend
  # assignments, S2 carries 0. Tier 2 should pull more weekend slots toward
  # S2 to balance the (target + carry-in) total.
  ops <- tibble::tibble(
    surname = c("S1", "S2", "J1", "J2"),
    name = "",
    role = c("senior", "senior", "nurse_2", "nurse_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-06", "2026-06-07")),
    weekday = c(6L, 7L), is_weekend = TRUE, is_holiday = FALSE,
    slot_kind = "weekend",
    slots = list(slots_for_kind("weekend"), slots_for_kind("weekend"))
  )
  rules <- load_rules(rules_path)
  rules$limits$min_free_weekends_per_month <- 0L
  # Make Tier 2 the dominant term.
  rules$fairness_weights$monthly_total <- 0L
  rules$fairness_weights$preference <- 0L
  rules$fairness_weights$weekend_holiday <- 100L

  carry <- tibble::tibble(
    op_idx = 1:4,
    operator_id = ops$surname,
    carry_count = c(2L, 0L, 0L, 0L)
  )
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(4)),
    calendar = dplyr::mutate(cal, day_idx = seq_len(2)),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = carry,
    preferences = NULL
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
  vals <- ompr::get_solution(sol, x[op, day, slot, role_pos])
  vals <- vals[vals$value > 0.5, ]
  # S1's target-month share should be <= S2's (carry-in penalty pushes S1 down).
  s1_count <- sum(vals$op == 1L)
  s2_count <- sum(vals$op == 2L)
  expect_lte(s1_count, s2_count)
})

test_that("Tier 3 soft preference reduces matching slot probability", {
  rules_path <- testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml")
  # 2 seniors + 2 juniors over 2 weekdays (Mon, Tue). Senior S1 has soft
  # avoid for weekday=1 (Mon). With high preference weight, the optimizer
  # should put S2 on Mon instead of S1.
  ops <- tibble::tibble(
    surname = c("S1", "S2", "J1", "J2"),
    name = "",
    role = c("senior", "senior", "nurse_2", "nurse_2"),
    part_time_pct = 100L,
    active_from = as.Date("2024-01-01"),
    active_to = as.Date("9999-12-31")
  )
  cal <- tibble::tibble(
    date = as.Date(c("2026-06-01", "2026-06-02")),
    weekday = c(1L, 2L), is_weekend = FALSE, is_holiday = FALSE,
    slot_kind = "weekday",
    slots = list(slots_for_kind("weekday"), slots_for_kind("weekday"))
  )
  rules <- load_rules(rules_path)
  # Make preferences dominant.
  rules$fairness_weights$monthly_total <- 0L
  rules$fairness_weights$weekend_holiday <- 0L
  rules$fairness_weights$preference <- 1000L

  prefs <- tibble::tibble(
    operator_id = "S1",
    weekday = 1L,
    slot_type = NA_character_,
    polarity = "avoid",
    hard = FALSE
  )
  ctx <- list(
    operators = dplyr::mutate(ops, operator_id = surname, op_idx = seq_len(4)),
    calendar = dplyr::mutate(cal, day_idx = seq_len(2)),
    rules = rules,
    absent_idx = matrix(integer(0), ncol = 2),
    carry_in = tibble::tibble(op_idx = 1:4, operator_id = ops$surname, carry_count = 0L),
    preferences = prefs
  )
  m <- build_milp(ctx)
  sol <- ompr::solve_model(m, ompr.roi::with_ROI(solver = "glpk"))
  expect_true(ompr::solver_status(sol) %in% c("optimal", "success"))
  vals <- ompr::get_solution(sol, x[op, day, slot, role_pos])
  vals <- vals[vals$value > 0.5, ]
  # S1 should not be on Monday (day 1) for any role.
  expect_false(any(vals$op == 1L & vals$day == 1L))
})
