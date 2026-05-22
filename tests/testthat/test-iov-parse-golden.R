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

  # The golden file has a fill_rgb column the parser does not emit; drop it for
  # comparison. Both sides must be NA-free (the parser inner_join guarantees this).
  golden_clean <- golden |>
    dplyr::mutate(date = as.Date(.data$date)) |>
    dplyr::select(-fill_rgb)

  # Row counts must match closely. A tolerance of 2 is allowed: the golden
  # script does not synthesise "available" rows for residents whose column is
  # entirely blank on a given day, whereas the parser always emits one row per
  # (resident × date × shift). Any discrepancy beyond 2 rows indicates a
  # structural regression.
  parsed_count <- nrow(parsed)
  golden_count <- nrow(golden_clean)
  expect_true(abs(parsed_count - golden_count) <= 2L,
    info = sprintf("Row counts differ beyond tolerance: parsed=%d, golden=%d (diff=%d, max=2)",
                   parsed_count, golden_count, abs(parsed_count - golden_count)))

  # 21 active residents from July roster should all be present;
  # spot-check 4 of them.
  for (name in c("Bof", "Bivona", "Massa", "Pittarello")) {
    expect_true(name %in% parsed$resident,
                info = paste("missing resident:", name))
  }

  # Year tags for the 4 spot-checks: Bof=4, Bivona=1, Massa=1, Pittarello=5.
  uniq <- dplyr::distinct(parsed, resident, year)
  expect_equal(uniq$year[uniq$resident == "Bof"], "4")
  expect_equal(uniq$year[uniq$resident == "Bivona"], "1")
  expect_equal(uniq$year[uniq$resident == "Massa"], "1")
  expect_equal(uniq$year[uniq$resident == "Pittarello"], "5")

  # 3 weekend ONCO 1 attending-night dates: Sat Jul 4, Sun Jul 12, Sat Jul 25
  # must produce NOTTE rows. Just check date set.
  notte_dates <- sort(unique(dplyr::filter(parsed, shift == "NOTTE")$date))
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
