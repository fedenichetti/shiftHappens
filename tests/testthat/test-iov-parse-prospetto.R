test_that("read_iov_prospetto parses weekend rows and skips title/header blocks", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_prospetto(fixture)

  out <- read_iov_prospetto(fixture)

  expect_s3_class(out, "tbl_df")
  expect_named(out, c("date", "dow", "day_unit", "night_unit"))
  expect_equal(nrow(out), 4L)
  expect_equal(out$date, as.Date(c("2026-07-04", "2026-07-05",
                                   "2026-07-11", "2026-07-12")))
  expect_equal(out$dow, c("Sab", "Dom", "Sab", "Dom"))
  expect_equal(out$night_unit,
               c("ONCOLOGIA 1", "ONCOLOGIA 2", "SENOLOGICA 1", "ONCOLOGIA 1"))
  expect_true(all(out$day_unit == "ANESTESTISTA"))
})

test_that("read_iov_prospetto errors on missing file", {
  expect_error(read_iov_prospetto("/no/such/file.xlsx"),
               "PROSPETTO file not found")
})
