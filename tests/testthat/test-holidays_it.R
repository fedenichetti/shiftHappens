test_that("easter_sunday returns known dates", {
  # Reference values from https://en.wikipedia.org/wiki/List_of_dates_for_Easter
  expect_equal(easter_sunday(2024), as.Date("2024-03-31"))
  expect_equal(easter_sunday(2025), as.Date("2025-04-20"))
  expect_equal(easter_sunday(2026), as.Date("2026-04-05"))
  expect_equal(easter_sunday(2027), as.Date("2027-03-28"))
  expect_equal(easter_sunday(2030), as.Date("2030-04-21"))
})

test_that("italian_holidays returns 12 dates per year", {
  h <- italian_holidays(2026)
  expect_s3_class(h, "tbl_df")
  expect_equal(nrow(h), 12L)
  expect_named(h, c("date", "name"))
  expect_s3_class(h$date, "Date")
})

test_that("italian_holidays contains fixed national dates", {
  h <- italian_holidays(2026)
  expect_true(as.Date("2026-01-01") %in% h$date)   # Capodanno
  expect_true(as.Date("2026-04-25") %in% h$date)   # Liberazione
  expect_true(as.Date("2026-05-01") %in% h$date)   # Lavoratori
  expect_true(as.Date("2026-06-02") %in% h$date)   # Repubblica
  expect_true(as.Date("2026-08-15") %in% h$date)   # Ferragosto
  expect_true(as.Date("2026-12-25") %in% h$date)   # Natale
  expect_true(as.Date("2026-12-26") %in% h$date)   # S. Stefano
})

test_that("italian_holidays includes Easter and Easter Monday", {
  h <- italian_holidays(2026)
  expect_true(as.Date("2026-04-05") %in% h$date)   # Pasqua
  expect_true(as.Date("2026-04-06") %in% h$date)   # Pasquetta
})

test_that("holidays_for_year merges YAML extras", {
  extras <- list(
    list(name = "S. Patrono", date = "12-04"),
    list(name = "Festa locale", date = "06-13")
  )
  h <- holidays_for_year(2026, holidays_extra = extras)
  expect_equal(nrow(h), 14L)
  expect_true(as.Date("2026-12-04") %in% h$date)
  expect_true(as.Date("2026-06-13") %in% h$date)
})

test_that("holidays_for_year handles empty extras", {
  expect_equal(nrow(holidays_for_year(2026, holidays_extra = list())), 12L)
  expect_equal(nrow(holidays_for_year(2026, holidays_extra = NULL)), 12L)
})

test_that("holidays_for_year rejects malformed extra dates", {
  bad <- list(list(name = "Bogus", date = "13-32"))
  expect_error(holidays_for_year(2026, holidays_extra = bad))
  not_a_string <- list(list(name = "Bogus", date = 1204))
  expect_error(holidays_for_year(2026, holidays_extra = not_a_string))
})
