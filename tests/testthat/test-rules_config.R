test_that("load_rules reads valid YAML", {
  r <- load_rules(testthat::test_path("..", "..", "inst", "examples", "rules_minimal.yaml"))
  expect_equal(r$unit$name, "Test Unit")
  expect_equal(r$limits$senior_max_per_month, 7L)
  expect_equal(r$fairness_weights$monthly_total, 100L)
  expect_equal(r$ui$primary_color, "#1ca5b8")
})

test_that("load_rules fills missing optional keys with defaults", {
  tmp <- tempfile(fileext = ".yaml")
  writeLines(c(
    "unit:",
    "  name: 'Minimal'",
    "roles:",
    "  primary: 'senior'",
    "  secondary: ['nurse_2']"
  ), tmp)
  r <- load_rules(tmp)
  # Defaults should backfill
  expect_equal(r$limits$senior_max_per_month, 7L)
  expect_equal(r$limits$rolling_history_months, 1L)
  expect_equal(r$solver$time_limit_seconds, 30L)
  unlink(tmp)
})

test_that("load_rules errors on missing required keys", {
  tmp <- tempfile(fileext = ".yaml")
  writeLines("unit: {name: 'NoRoles'}", tmp)
  expect_error(load_rules(tmp), regexp = "roles")
  unlink(tmp)
})

test_that("load_rules errors on wrong type", {
  tmp <- tempfile(fileext = ".yaml")
  writeLines(c(
    "unit:",
    "  name: 'X'",
    "roles:",
    "  primary: 'senior'",
    "  secondary: ['nurse_2']",
    "limits:",
    "  senior_max_per_month: 'seven'"   # wrong type
  ), tmp)
  expect_error(load_rules(tmp), regexp = "senior_max_per_month")
  unlink(tmp)
})
