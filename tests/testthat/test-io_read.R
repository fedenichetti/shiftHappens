fixture <- system.file("examples", "may2026_workbook.xlsx", package = "shifthappens")

test_that("read_workbook returns a list of 5 named tibbles", {
  wb <- read_workbook(fixture)
  expect_named(wb, c("operators", "history", "absences", "preferences", "month"))
  for (s in names(wb)) expect_s3_class(wb[[s]], "tbl_df")
})

test_that("read_workbook coerces operators columns", {
  wb <- read_workbook(fixture)
  ops <- wb$operators
  expect_s3_class(ops$active_from, "Date")
  expect_s3_class(ops$active_to,   "Date")
  expect_type(ops$part_time_pct, "integer")
  expect_true(all(ops$role %in% c("senior", "nurse_2", "oss_2")))
})

test_that("read_workbook coerces month to YYYY-MM string", {
  wb <- read_workbook(fixture)
  expect_match(wb$month$month[1], "^[0-9]{4}-[0-9]{2}$")
})

test_that("read_workbook errors when a sheet is missing", {
  tmp <- tempfile(fileext = ".xlsx")
  wb <- openxlsx2::wb_workbook()
  wb$add_worksheet("operators")
  openxlsx2::wb_save(wb, tmp)
  expect_error(read_workbook(tmp), regexp = "missing.*sheet")
  unlink(tmp)
})
