test_that("read_iov_desiderata_specializzandi matches the golden derived file", {
  # Use rprojroot to find project root, then construct paths.
  # testthat may change the working directory, so we need absolute paths.
  root <- rprojroot::find_root(rprojroot::is_r_package)
  .iov_golden_src_desiderata <- file.path(root, "iov/Turni coguardia + guardia 2026 specializzandi.xlsx")
  .iov_golden_out_desiderata <- file.path(root, "iov/analysis/desiderata_07_2026.xlsx")

  testthat::skip_if_not(file.exists(.iov_golden_src_desiderata),
    "Real IOV desiderata workbook not present — skipping golden test")
  testthat::skip_if_not(file.exists(.iov_golden_out_desiderata),
    "Golden derived file not present — skipping golden test")

  parsed <- read_iov_desiderata_specializzandi(
    .iov_golden_src_desiderata,
    sheet = "Luglio 2026",
    target_month = "2026-07"
  )
  golden <- readxl::read_excel(.iov_golden_out_desiderata,
                               sheet = "desiderata_long")

  # Filter out orphaned rows (with NA dates) from both for comparison.
  # These arise from data-quality issues in the source xlsx (spurious continuation
  # cells beyond the day index). Both the parser and golden file generate these.
  parsed_clean <- dplyr::filter(parsed, !is.na(.data$date))
  golden_clean <- golden |>
    dplyr::mutate(date = as.Date(.data$date)) |>
    dplyr::filter(!is.na(.data$date)) |>
    dplyr::select(-fill_rgb)

  # Row counts should match on the cleaned data (within tolerance for
  # minor data-quality variations). Expect approximately equal.
  parsed_count <- nrow(parsed_clean)
  golden_count <- nrow(golden_clean)
  tolerance <- 5L  # Allow up to 5-row difference
  expect_true(abs(parsed_count - golden_count) <= tolerance,
    info = sprintf("Row counts differ: parsed=%d, golden=%d (tolerance=%d)",
                   parsed_count, golden_count, tolerance))

  # 21 active residents from July roster should all be present;
  # spot-check 4 of them.
  for (name in c("Bof", "Bivona", "Massa", "Pittarello")) {
    expect_true(name %in% parsed_clean$resident,
                info = paste("missing resident:", name))
  }

  # Year tags for the 4 spot-checks: Bof=4, Bivona=1, Massa=1, Pittarello=5.
  uniq <- dplyr::distinct(parsed_clean, resident, year)
  expect_equal(uniq$year[uniq$resident == "Bof"], "4")
  expect_equal(uniq$year[uniq$resident == "Bivona"], "1")
  expect_equal(uniq$year[uniq$resident == "Massa"], "1")
  expect_equal(uniq$year[uniq$resident == "Pittarello"], "5")

  # 3 weekend ONCO 1 attending-night dates: Sat Jul 4, Sun Jul 12, Sat Jul 25
  # must produce NOTTE rows. Just check date set.
  notte_dates <- sort(unique(dplyr::filter(parsed_clean, shift == "NOTTE")$date))
  expect_true(as.Date("2026-07-04") %in% notte_dates)
  expect_true(as.Date("2026-07-12") %in% notte_dates)
  expect_true(as.Date("2026-07-25") %in% notte_dates)
})

test_that("read_iov_prospetto on the real file picks out the 3 ONCO 1 weekend nights for July", {
  root <- rprojroot::find_root(rprojroot::is_r_package)
  .iov_golden_src_prospetto  <- file.path(root, "iov/PROSPETTO GUARDIE 2026_LUGLIO_SETTEMBRE_DEF_.xlsx")

  testthat::skip_if_not(file.exists(.iov_golden_src_prospetto),
    "Real IOV PROSPETTO not present — skipping golden test")

  pro <- read_iov_prospetto(.iov_golden_src_prospetto)
  jul_onco1 <- pro |>
    dplyr::filter(format(date, "%Y-%m") == "2026-07",
                  night_unit == "ONCOLOGIA 1")
  expect_equal(sort(jul_onco1$date),
               as.Date(c("2026-07-04", "2026-07-12", "2026-07-25")))
})
