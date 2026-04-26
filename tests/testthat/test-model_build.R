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
