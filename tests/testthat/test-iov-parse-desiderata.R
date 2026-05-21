test_that(".iov_shared_strings decodes <si><t> wrappers", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_desiderata(fixture)
  wb <- openxlsx2::wb_load(fixture)
  ss <- .iov_shared_strings(wb)
  # We injected 4 surnames + day-of-week text — at minimum those should appear.
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
