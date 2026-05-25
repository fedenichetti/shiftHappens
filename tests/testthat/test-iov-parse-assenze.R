test_that("read_iov_assenze_specialisti parses AF/AC/partial qualifiers", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_assenze(fixture)

  out <- read_iov_assenze_specialisti(fixture, target_month = "2026-07")

  expect_s3_class(out, "tbl_df")
  expect_named(out, c("date", "dow", "person", "absence_type", "slot"))

  # Lonardi: AF Jul 2 + AF Jul 3
  lonardi <- dplyr::filter(out, person == "Lonardi")
  expect_equal(nrow(lonardi), 2L)
  expect_true(all(lonardi$absence_type == "ferie"))
  expect_true(all(lonardi$slot == "full_day"))

  # Procaccio: AC Jul 3 + "AF pomeriggio" Jul 4 + "no guardia" Jul 5
  proc <- dplyr::filter(out, person == "Procaccio")
  expect_equal(nrow(proc), 3L)
  expect_equal(proc$absence_type, c("congresso", "ferie", "no_guardia"))
  expect_equal(proc$slot,         c("full_day", "pomeriggio", "full_day"))
})

test_that("read_iov_assenze_specialisti is case-insensitive (AF, Af, af)", {
  fixture <- tempfile(fileext = ".xlsx")
  wb <- openxlsx2::wb_workbook()$add_worksheet("Foglio1")
  wb <- openxlsx2::wb_add_data(wb, sheet = 1,
    x = data.frame(
      A = c(NA, NA, "SPECIALISTI", "Tester"),
      B = c("MER", 1, NA, "AF"),
      C = c("GIO", 2, NA, "Af"),
      D = c("VEN", 3, NA, "af"),
      stringsAsFactors = FALSE),
    dims = "A1", col_names = FALSE)
  openxlsx2::wb_save(wb, fixture, overwrite = TRUE)

  out <- read_iov_assenze_specialisti(fixture, target_month = "2026-07")
  expect_equal(nrow(out), 3L)
  expect_true(all(out$absence_type == "ferie"))
})
