test_that(".iov_shared_strings decodes <si><t> wrappers preserving SST order and duplicates", {
  # Use Option C: inject wb$sharedStrings directly to test the decoder in
  # isolation, bypassing openxlsx2's encoding heuristic (small workbooks are
  # stored as inlineStr, not SST, so wb$sharedStrings would be empty).
  # Production IOV files have ~470 SST entries with duplicates (e.g. "AF"
  # appears at indices 344-348); unique() would collapse those, shifting every
  # subsequent index. The helper must return a vector positionally identical
  # to the SST — no deduplication.
  wb <- openxlsx2::wb_workbook()$add_worksheet("Sheet1")
  # Manually set the SST: two entries for "Rossi" and two for "Bianchi"
  # so we can verify that duplicates are preserved and order is maintained.
  wb$sharedStrings <- c(
    "<si><t>Rossi</t></si>",
    "<si><t>Bianchi</t></si>",
    "<si><t>Rossi</t></si>",   # duplicate — must NOT be collapsed
    "<si><t>Bianchi</t></si>"  # duplicate — must NOT be collapsed
  )
  ss <- .iov_shared_strings(wb)
  expect_equal(length(ss), 4L)          # duplicates preserved
  expect_equal(ss[1L], "Rossi")         # positional index 0 → R index 1
  expect_equal(ss[2L], "Bianchi")       # positional index 1 → R index 2
  expect_equal(ss[3L], "Rossi")         # duplicate at index 2 intact
  expect_equal(ss[4L], "Bianchi")       # duplicate at index 3 intact
  expect_true("Rossi" %in% ss)
  expect_true("Bianchi" %in% ss)
})

test_that(".iov_style_to_fill_rgb resolves row-3 fills correctly", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_desiderata(fixture)
  wb <- openxlsx2::wb_load(fixture)
  fill_lookup <- .iov_style_to_fill_rgb_lookup(wb)

  # Row 3 col C (Rossi) was filled FFB4A7D6 (viola → 1°)
  cc <- wb$worksheets[[1]]$sheet_data$cc
  c3 <- cc[cc$r == "C3", ]
  expect_true(nrow(c3) >= 1L)
  expect_equal(fill_lookup(c3$c_s[1]), "FFB4A7D6")
})

test_that(".iov_extract_residents reads row 3 names and derives year from fill", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_desiderata(fixture)
  wb <- openxlsx2::wb_load(fixture)

  res <- .iov_extract_residents(wb, sheet = "Luglio 2026")

  expect_s3_class(res, "tbl_df")
  expect_named(res, c("col", "resident", "year"))
  expect_equal(nrow(res), 4L)
  expect_equal(res$resident, c("Rossi", "Bianchi", "Verdi", "Neri"))
  expect_equal(res$year, c("1", "2", "3", "4"))
})

test_that(".iov_extract_residents drops 'Assegnazione …BOZZA' template cols", {
  fixture <- tempfile(fileext = ".xlsx")
  wb <- openxlsx2::wb_workbook()$add_worksheet("Test")
  wb <- openxlsx2::wb_add_data(wb, sheet = 1,
    x = matrix(c(NA, NA, "Rossi", "Assegnazione guardia BOZZA"),
               nrow = 1),
    dims = "A3", col_names = FALSE)
  wb <- openxlsx2::wb_add_fill(wb, sheet = 1, dims = "C3",
                                color = openxlsx2::wb_color(hex = "FFB4A7D6"))
  openxlsx2::wb_save(wb, fixture, overwrite = TRUE)

  wb2 <- openxlsx2::wb_load(fixture)
  res <- .iov_extract_residents(wb2, sheet = "Test")
  expect_equal(nrow(res), 1L)
  expect_equal(res$resident, "Rossi")
})

test_that("read_iov_desiderata_specializzandi long-format covers all (resident × date × shift)", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_desiderata(fixture)

  out <- read_iov_desiderata_specializzandi(fixture,
    sheet = "Luglio 2026", target_month = "2026-07")

  expect_s3_class(out, "tbl_df")
  expect_named(out, c("date", "dow", "shift", "resident", "year",
                      "status", "preference", "raw_value"))

  # 4 residents × 7 day-rows (3 weekdays + 2 weekend × 2 rows) = 28 rows.
  expect_equal(nrow(out), 28L)
  expect_equal(sort(unique(out$shift)), c("GIORNO", "NOTTE"))

  # Spot-check: Bianchi on Wed Jul 1 row had "x" → unavailable_soft, NOTTE shift.
  bw1 <- dplyr::filter(out, resident == "Bianchi", date == as.Date("2026-07-01"))
  expect_equal(nrow(bw1), 1L)
  expect_equal(bw1$shift, "NOTTE")
  expect_equal(bw1$status, "unavailable_soft")
  expect_equal(bw1$raw_value, "x")

  # Spot-check: Sat Jul 4 row 7 (seq=1) = GIORNO, row 8 (seq=2) = NOTTE.
  sat <- dplyr::filter(out, date == as.Date("2026-07-04"))
  expect_equal(nrow(sat), 8L)  # 4 residents × 2 shifts
  bianchi_sat <- dplyr::filter(sat, resident == "Bianchi")
  expect_equal(bianchi_sat$status[bianchi_sat$shift == "GIORNO"], "unavailable_soft")
  expect_equal(bianchi_sat$status[bianchi_sat$shift == "NOTTE"], "available")

  # Yellow fill: Rossi Fri Jul 3 (col C row 6) + Bianchi Sun Jul 5 GIORNO (col D row 9).
  fav <- dplyr::filter(out, preference == "favorite")
  expect_equal(nrow(fav), 2L)
  expect_true(all(c("Rossi", "Bianchi") %in% fav$resident))
})
