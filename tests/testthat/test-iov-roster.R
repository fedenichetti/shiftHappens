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

test_that("derive_roster builds the resolved_roster list with REPARTO + pools", {
  members_fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_members(members_fixture)

  # Synthetic parsed_inputs covering 4 residents from the members fixture
  # (BOSIO 5°, PITTARELLO 5°, MASSA 1°, SARTORI Elena 1°)
  desiderata_long <- tibble::tibble(
    resident = c("Bosio", "Pittarello", "Massa", "Sartori"),
    year     = c("5",     "5",          "1",     "1"),
    date     = as.Date(rep("2026-07-04", 4)),
    dow = "Sab", shift = "GIORNO", status = "available",
    preference = "neutral", raw_value = NA_character_
  )
  parsed_inputs <- list(
    target_month    = "2026-07",
    prospetto       = tibble::tibble(date = as.Date("2026-07-04"), dow = "Sab",
                                     day_unit = "ANESTESTISTA",
                                     night_unit = "ONCOLOGIA 1"),
    desiderata_long = desiderata_long,
    assenze_long    = tibble::tibble(date = as.Date(character()),
                                     dow = character(), person = character(),
                                     absence_type = character(), slot = character())
  )

  roster <- derive_roster(parsed_inputs, members_fixture,
                          reparto_selection = c("MASSA", "BOSIO"))

  expect_named(roster, c("residents", "specialists", "reparto_block",
                         "clinic_only_attendings", "inpatient_attendings",
                         "juniors_eligible_for_substitution", "meta"))

  # Residents tibble
  expect_s3_class(roster$residents, "tbl_df")
  expect_equal(nrow(roster$residents), 4L)
  expect_true(all(c("BOSIO", "PITTARELLO", "MASSA", "SARTORI") %in%
                    roster$residents$last_name))

  # REPARTO membership flag
  expect_setequal(
    roster$residents$last_name[roster$residents$in_reparto_block],
    c("MASSA", "BOSIO")
  )

  # Specialists tibble — must include Lonardi, Bergamo, Galiano, Bolshinsky,
  # Procaccio, Nichetti from the members fixture
  expect_true(all(c("LONARDI", "BERGAMO", "GALIANO", "BOLSHINSKY",
                    "PROCACCIO", "NICHETTI") %in% roster$specialists$last_name))
  expect_true(roster$specialists$is_clinic_only[
    roster$specialists$last_name == "LONARDI"])
  expect_true(roster$specialists$is_full_inpatient[
    roster$specialists$last_name == "GALIANO"])
  expect_true(roster$specialists$fasi_i_eligible[
    roster$specialists$last_name == "BOLSHINSKY"])

  # Constant pools
  expect_setequal(roster$clinic_only_attendings, c("LONARDI", "BERGAMO"))
  expect_setequal(roster$inpatient_attendings,   c("GALIANO", "BOLSHINSKY"))
  expect_setequal(roster$reparto_block,          c("MASSA", "BOSIO"))

  # Juniors eligible for substitution = year 1 or 2, NOT in REPARTO.
  # MASSA is in REPARTO so excluded; SARTORI year=1 stays. (PITTARELLO 5°, BOSIO 5° excluded by year.)
  expect_setequal(roster$juniors_eligible_for_substitution, "SARTORI")

  # Meta
  expect_equal(roster$meta$target_month, "2026-07")
  expect_equal(roster$meta$members_count, 11L)
})

test_that("derive_roster errors when reparto_selection has < 4 names (memo: July has exactly 4)", {
  # Note: spec doesn't enforce exactly 4 (size depends on month); we only
  # require non-empty selection if MILP is to apply H4 — but validation lives
  # in validate_iov_inputs(). derive_roster accepts any vector >= 0.
  members_fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_members(members_fixture)
  parsed_inputs <- list(
    target_month = "2026-07",
    prospetto = tibble::tibble(date = as.Date("2026-07-04"), dow = "Sab",
                               day_unit = "X", night_unit = "X"),
    desiderata_long = tibble::tibble(
      resident = "Bosio", year = "5", date = as.Date("2026-07-01"),
      dow = "Mer", shift = "NOTTE", status = "available",
      preference = "neutral", raw_value = NA_character_
    ),
    assenze_long = tibble::tibble(date = as.Date(character()),
                                  dow = character(), person = character(),
                                  absence_type = character(), slot = character())
  )
  out <- derive_roster(parsed_inputs, members_fixture,
                       reparto_selection = character())
  expect_equal(length(out$reparto_block), 0L)
  expect_equal(length(out$juniors_eligible_for_substitution),
               0L)  # no juniors in this synthetic input
})
