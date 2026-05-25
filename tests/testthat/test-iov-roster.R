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

test_that(".iov_normalize_name handles apostrophe drift and casing", {
  expect_equal(.iov_normalize_name("Solda'"),  "SOLDA")
  expect_equal(.iov_normalize_name("SOLDA"),    "SOLDA")
  expect_equal(.iov_normalize_name("Trovò"),   "TROVÒ")
  expect_equal(.iov_normalize_name("Trovò'"),  "TROVÒ")
  expect_equal(.iov_normalize_name("Di Marco"), "DI MARCO")
  expect_equal(.iov_normalize_name("  Bosio "), "BOSIO")
  expect_equal(.iov_normalize_name("Di  Marco"), "DI MARCO")  # double space
  expect_true(is.na(.iov_normalize_name(NA_character_)))
})

test_that(".iov_match_residents joins by normalised surname + year", {
  members <- tibble::tibble(
    last_name = c("BOSIO", "MASSA", "SARTORI", "SARTORI"),
    first_name = c("Marco", "Elena", "Beatrice", "Elena"),
    role = rep("Specializzando", 4),
    in_guardie_rotation = rep(TRUE, 4),
    primary_group = NA_character_, subgroup_secondary = NA_character_,
    reperibile_fasi_i = rep(FALSE, 4), notes = c("", "", "Beatrice (5°)", "Elena (1°)"),
    unit = rep("ONCO 1", 4), active_months_2026 = rep("all", 4)
  )
  desiderata_residents <- tibble::tibble(
    resident = c("Bosio", "Massa", "Sartori", "Sartori"),
    year     = c("5",     "1",     "5",       "1")
  )

  out <- .iov_match_residents(desiderata_residents, members)

  expect_s3_class(out, "tbl_df")
  expect_named(out, c("desiderata_name", "year", "last_name_resolved",
                      "first_name_resolved", "matched", "ambiguous"))
  expect_equal(nrow(out), 4L)
  expect_true(all(out$matched))
  expect_false(any(out$ambiguous))

  # Sartori year=5 → Beatrice; Sartori year=1 → Elena
  sartori_5 <- out[out$desiderata_name == "Sartori" & out$year == "5", ]
  expect_equal(sartori_5$first_name_resolved, "Beatrice")
  sartori_1 <- out[out$desiderata_name == "Sartori" & out$year == "1", ]
  expect_equal(sartori_1$first_name_resolved, "Elena")
})

test_that(".iov_match_residents flags ambiguous when year doesn't disambiguate", {
  members <- tibble::tibble(
    last_name = c("SARTORI", "SARTORI"),
    first_name = c("Beatrice", "Elena"),
    role = rep("Specializzando", 2), in_guardie_rotation = rep(TRUE, 2),
    primary_group = NA_character_, subgroup_secondary = NA_character_,
    reperibile_fasi_i = rep(FALSE, 2), notes = c("Beatrice (5°)", "Elena (1°)"),
    unit = rep("ONCO 1", 2), active_months_2026 = rep("all", 2)
  )
  # Desiderata Sartori with year="unknown" — neither Beatrice nor Elena.
  desiderata_residents <- tibble::tibble(
    resident = "Sartori", year = "unknown"
  )

  out <- .iov_match_residents(desiderata_residents, members)
  expect_equal(nrow(out), 1L)
  expect_false(out$matched)
  expect_true(out$ambiguous)
  expect_true(is.na(out$last_name_resolved))
})
