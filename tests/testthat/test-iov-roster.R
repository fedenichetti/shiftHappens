test_that("read_iov_members loads canonical member list with normalised types", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_members(fixture)

  m <- read_iov_members(fixture)

  expect_s3_class(m, "tbl_df")
  expect_true(all(c("last_name", "first_name", "role", "unit",
                    "primary_group", "in_guardie_rotation",
                    "reperibile_fasi_i") %in% names(m)))
  expect_equal(nrow(m), 11L)

  # Logical coercion: in_guardie_rotation
  expect_type(m$in_guardie_rotation, "logical")
  expect_equal(sum(m$in_guardie_rotation), 7L)
  expect_equal(sum(!m$in_guardie_rotation), 4L)

  # Logical coercion: reperibile_fasi_i
  expect_type(m$reperibile_fasi_i, "logical")
  expect_true(m$reperibile_fasi_i[m$last_name == "BOLSHINSKY"])
  expect_false(m$reperibile_fasi_i[m$last_name == "LONARDI"])

  # Uppercase enforcement on last_name
  expect_true(all(m$last_name == toupper(m$last_name)))
})

test_that("read_iov_members errors on missing file", {
  expect_error(read_iov_members("/no/such/file.xlsx"),
               "IOV_MEMBERS file not found")
})
