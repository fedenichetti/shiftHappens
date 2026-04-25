test_that("easter_sunday returns known dates", {
  # Reference values from https://en.wikipedia.org/wiki/List_of_dates_for_Easter
  expect_equal(easter_sunday(2024), as.Date("2024-03-31"))
  expect_equal(easter_sunday(2025), as.Date("2025-04-20"))
  expect_equal(easter_sunday(2026), as.Date("2026-04-05"))
  expect_equal(easter_sunday(2027), as.Date("2027-03-28"))
  expect_equal(easter_sunday(2030), as.Date("2030-04-21"))
})
