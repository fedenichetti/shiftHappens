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

test_that("build_calendar marks holidays and assigns slot_kind", {
  cal <- build_calendar(2026, 5, holidays_extra = list())
  # 2026-05-01 is Friday (weekday) but Festa dei Lavoratori
  may1 <- cal[cal$date == as.Date("2026-05-01"), ]
  expect_true(may1$is_holiday)
  expect_equal(may1$slot_kind, "holiday")
  # 2026-05-04 is Monday, no holiday
  may4 <- cal[cal$date == as.Date("2026-05-04"), ]
  expect_false(may4$is_holiday)
  expect_equal(may4$slot_kind, "weekday")
  # 2026-05-02 is Saturday, no holiday
  may2 <- cal[cal$date == as.Date("2026-05-02"), ]
  expect_false(may2$is_holiday)
  expect_equal(may2$slot_kind, "weekend")
})

test_that("build_calendar slots list-column has correct shape", {
  cal <- build_calendar(2026, 5, holidays_extra = list())
  weekday_row  <- cal[cal$date == as.Date("2026-05-04"), ]
  weekend_row  <- cal[cal$date == as.Date("2026-05-02"), ]
  holiday_row  <- cal[cal$date == as.Date("2026-05-01"), ]
  expect_equal(nrow(weekday_row$slots[[1]]),  2L)   # 1°-night, 2°-night
  expect_equal(nrow(weekend_row$slots[[1]]),  4L)   # 1°-D, 1°-N, 2°-D, 2°-N
  expect_equal(nrow(holiday_row$slots[[1]]),  4L)   # holiday treated as weekend
})
