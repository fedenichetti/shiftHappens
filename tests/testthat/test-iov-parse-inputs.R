test_that("read_iov_inputs combines all 3 parsers and validates month consistency", {
  pro <- tempfile(fileext = ".xlsx")
  des <- tempfile(fileext = ".xlsx")
  ass <- tempfile(fileext = ".xlsx")
  .iov_fx_prospetto(pro)
  .iov_fx_desiderata(des, sheet = "Luglio 2026")
  .iov_fx_assenze(ass)

  out <- read_iov_inputs(
    prospetto_path  = pro,
    desiderata_path = des,
    desiderata_sheet = "Luglio 2026",
    assenze_path    = ass,
    target_month    = "2026-07"
  )

  expect_named(out, c("target_month", "prospetto", "desiderata_long",
                      "assenze_long"))
  expect_equal(out$target_month, "2026-07")
  expect_s3_class(out$prospetto, "tbl_df")
  expect_s3_class(out$desiderata_long, "tbl_df")
  expect_s3_class(out$assenze_long, "tbl_df")

  # PROSPETTO must include at least one row in July 2026.
  expect_true(any(format(out$prospetto$date, "%Y-%m") == "2026-07"))

  # All desiderata dates must lie in July 2026.
  expect_true(all(format(out$desiderata_long$date, "%Y-%m") == "2026-07"))
})

test_that("read_iov_inputs errors when target month has no PROSPETTO rows", {
  pro <- tempfile(fileext = ".xlsx")
  des <- tempfile(fileext = ".xlsx")
  ass <- tempfile(fileext = ".xlsx")
  .iov_fx_prospetto(pro)
  .iov_fx_desiderata(des, sheet = "Luglio 2026")
  .iov_fx_assenze(ass)

  expect_error(
    read_iov_inputs(prospetto_path = pro, desiderata_path = des,
                    desiderata_sheet = "Luglio 2026", assenze_path = ass,
                    target_month = "2026-12"),
    "no PROSPETTO rows for target month"
  )
})
