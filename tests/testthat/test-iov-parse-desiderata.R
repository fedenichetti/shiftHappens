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
