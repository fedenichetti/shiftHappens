fixture <- testthat::test_path("..", "..", "inst", "examples", "may2026_workbook.xlsx")

test_that("validate_inputs returns no errors on the May 2026 fixture", {
  wb <- read_workbook(fixture)
  issues <- validate_inputs(wb)
  expect_s3_class(issues, "tbl_df")
  expect_named(issues, c("severity", "sheet", "row", "column", "message"))
  expect_equal(sum(issues$severity == "error"), 0L)
})

test_that("validate_inputs flags absent operator referenced in absences", {
  wb <- read_workbook(fixture)
  wb$absences <- tibble::tibble(
    operator_id = "Ghost",
    date_from   = as.Date("2026-06-01"),
    date_to     = as.Date("2026-06-02"),
    type        = "vacation"
  )
  issues <- validate_inputs(wb)
  expect_true(any(issues$severity == "error" &
                  grepl("operator_id 'Ghost'", issues$message)))
})

test_that("validate_inputs flags too few seniors", {
  wb <- read_workbook(fixture)
  wb$operators <- wb$operators[wb$operators$role != "senior", ]
  issues <- validate_inputs(wb)
  expect_true(any(issues$severity == "error" &
                  grepl("at least 1 senior", issues$message)))
})

test_that("validate_inputs flags reversed absence dates", {
  wb <- read_workbook(fixture)
  wb$absences <- tibble::tibble(
    operator_id = wb$operators$surname[1],
    date_from = as.Date("2026-06-10"),
    date_to   = as.Date("2026-06-05"),
    type      = "vacation"
  )
  issues <- validate_inputs(wb)
  expect_true(any(issues$severity == "error" &
                  grepl("date_from > date_to", issues$message)))
})

test_that("validate_inputs flags invalid weekday in preferences", {
  wb <- read_workbook(fixture)
  wb$preferences <- tibble::tibble(
    operator_id = wb$operators$surname[1],
    weekday = 9L,
    slot_type = NA_character_,
    polarity = "avoid",
    hard = FALSE
  )
  issues <- validate_inputs(wb)
  expect_true(any(issues$severity == "error" &
                  grepl("weekday", issues$message)))
})

test_that("validate_inputs flags too few secondary operators", {
  wb <- read_workbook(fixture)
  wb$operators <- wb$operators[wb$operators$role == "senior", ]
  issues <- validate_inputs(wb)
  expect_true(any(issues$severity == "error" &
                  grepl("secondary", issues$message)))
})

test_that("validate_inputs flags invalid history slot enum", {
  wb <- read_workbook(fixture)
  wb$history$slot[1] <- "bogus_slot"
  issues <- validate_inputs(wb)
  expect_true(any(issues$severity == "error" &
                  issues$sheet == "history" &
                  issues$column == "slot"))
})

test_that("validate_inputs flags invalid history role_slot", {
  wb <- read_workbook(fixture)
  wb$history$role_slot[1] <- "third"
  issues <- validate_inputs(wb)
  expect_true(any(issues$severity == "error" &
                  issues$sheet == "history" &
                  issues$column == "role_slot"))
})

test_that("validate_inputs flags missing operator in history", {
  wb <- read_workbook(fixture)
  wb$history$operator_id[1] <- "Phantom"
  issues <- validate_inputs(wb)
  expect_true(any(issues$severity == "error" &
                  issues$sheet == "history" &
                  grepl("Phantom", issues$message)))
})

test_that("validate_inputs flags invalid preferences slot_type and polarity", {
  wb <- read_workbook(fixture)
  wb$preferences <- tibble::tibble(
    operator_id = wb$operators$surname[1],
    weekday = 4L,
    slot_type = "afternoon",
    polarity = "neutral",
    hard = FALSE
  )
  issues <- validate_inputs(wb)
  expect_true(any(issues$severity == "error" &
                  issues$column == "slot_type"))
  expect_true(any(issues$severity == "error" &
                  issues$column == "polarity"))
})

test_that("validate_inputs flags unparseable month and past month", {
  wb <- read_workbook(fixture)
  wb$month <- tibble::tibble(month = "not-a-month")
  issues <- validate_inputs(wb)
  expect_true(any(issues$severity == "error" &
                  issues$sheet == "month" &
                  grepl("not parseable", issues$message)))

  wb2 <- read_workbook(fixture)
  wb2$month <- tibble::tibble(month = "2020-01")
  issues2 <- validate_inputs(wb2)
  expect_true(any(issues2$severity == "error" &
                  issues2$sheet == "month" &
                  grepl("past", issues2$message)))
})
