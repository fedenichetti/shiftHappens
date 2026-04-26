test_that("month_days returns correct day count for May 2026", {
  d <- month_days(2026, 5)
  expect_equal(nrow(d), 31L)
  expect_equal(d$date[1], as.Date("2026-05-01"))
  expect_equal(d$date[31], as.Date("2026-05-31"))
  expect_named(d, c("date", "weekday", "is_weekend"))
})

test_that("month_days flags Saturday and Sunday as weekend", {
  d <- month_days(2026, 5)
  # 2026-05-02 is Saturday, 2026-05-03 is Sunday
  expect_true(d$is_weekend[d$date == as.Date("2026-05-02")])
  expect_true(d$is_weekend[d$date == as.Date("2026-05-03")])
  # 2026-05-04 is Monday
  expect_false(d$is_weekend[d$date == as.Date("2026-05-04")])
})

test_that("month_days weekday is 1 for Monday, 7 for Sunday", {
  d <- month_days(2026, 5)
  expect_equal(d$weekday[d$date == as.Date("2026-05-04")], 1L) # Mon
  expect_equal(d$weekday[d$date == as.Date("2026-05-03")], 7L) # Sun
})

test_that("month_days handles February leap and non-leap", {
  expect_equal(nrow(month_days(2024, 2)), 29L)
  expect_equal(nrow(month_days(2026, 2)), 28L)
})
