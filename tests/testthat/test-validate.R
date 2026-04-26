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
