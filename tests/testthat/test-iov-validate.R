fixture_roster <- function() {
  # Build a minimal resolved_roster structure for tests.
  list(
    residents = tibble::tibble(
      last_name = c("BOSIO", "MASSA", NA),  # one row failed matching
      first_name = c("Marco", "Elena", NA),
      desiderata_name = c("Bosio", "Massa", "Sartori"),
      year = c("5", "1", "unknown"),
      matched = c(TRUE, TRUE, FALSE),
      ambiguous = c(FALSE, FALSE, TRUE),
      in_reparto_block = c(FALSE, FALSE, FALSE)
    ),
    specialists = tibble::tibble(
      last_name = c("LONARDI", "PROCACCIO"),
      first_name = c("Sara", "Giorgio"),
      role = c("Direttrice", "Specialista"),
      primary_group = c("Direzione", "GASTROENTERICO"),
      subgroup_secondary = c(NA_character_, "Pancreas"),
      in_guardie_rotation = c(FALSE, TRUE),
      fasi_i_eligible = c(FALSE, FALSE),
      is_clinic_only = c(TRUE, FALSE),
      is_full_inpatient = c(FALSE, FALSE)
    ),
    reparto_block                     = c("MASSA"),
    clinic_only_attendings            = c("LONARDI", "BERGAMO"),
    inpatient_attendings              = c("GALIANO", "BOLSHINSKY"),
    juniors_eligible_for_substitution = c("MASSA"),
    meta = list(target_month = "2026-07", members_count = 11L,
                ambiguous_names = "Sartori")
  )
}

fixture_inputs <- function() {
  list(
    target_month = "2026-07",
    prospetto = tibble::tibble(
      date = as.Date(c("2026-07-04", "2026-07-05")),
      dow = c("Sab", "Dom"),
      day_unit = c("ANESTESTISTA", "ANESTESTISTA"),
      night_unit = c("ONCOLOGIA 1", "ONCOLOGIA 2")
    ),
    desiderata_long = tibble::tibble(
      resident = c("Bosio", "Massa"), year = c("5", "1"),
      date = as.Date(rep("2026-07-04", 2)), dow = "Sab",
      shift = "GIORNO", status = "available",
      preference = "neutral", raw_value = NA_character_
    ),
    assenze_long = tibble::tibble(
      date = as.Date("2026-07-02"), dow = "Gio",
      person = "Procaccio", absence_type = "ferie", slot = "full_day"
    )
  )
}

test_that(".iov_check_unknown_residents flags assenze rows referencing strangers", {
  r <- fixture_roster()
  i <- fixture_inputs()

  # Happy path: Procaccio is a known specialist → no blockers
  expect_equal(.iov_check_unknown_residents(i, r), character(0))

  # Inject a stranger
  i$assenze_long <- dplyr::bind_rows(i$assenze_long, tibble::tibble(
    date = as.Date("2026-07-03"), dow = "Ven",
    person = "Stranieri", absence_type = "ferie", slot = "full_day"
  ))
  blockers <- .iov_check_unknown_residents(i, r)
  expect_length(blockers, 1L)
  expect_match(blockers, "Stranieri")
})

test_that(".iov_check_ambiguous_sartori flags unresolved ambiguity", {
  r <- fixture_roster()
  blockers <- .iov_check_ambiguous_sartori(r)
  expect_length(blockers, 1L)
  expect_match(blockers, "Sartori")
})

test_that(".iov_check_unknown_years flags residents with year='unknown'", {
  r <- fixture_roster()  # Sartori has year='unknown'
  blockers <- .iov_check_unknown_years(r)
  expect_length(blockers, 1L)
  expect_match(blockers, "Sartori")
})

test_that(".iov_check_reparto_validity flags names not in resident pool", {
  r <- fixture_roster()
  # MASSA is in the pool → no blocker
  expect_equal(.iov_check_reparto_validity(r), character(0))
  # Inject a non-resident name into REPARTO
  r$reparto_block <- c(r$reparto_block, "GHOST")
  blockers <- .iov_check_reparto_validity(r)
  expect_length(blockers, 1L)
  expect_match(blockers, "GHOST")
})

test_that(".iov_check_month_consistency flags PROSPETTO without target month rows", {
  i <- fixture_inputs()
  expect_equal(.iov_check_month_consistency(i), character(0))

  # Set target month to one with no PROSPETTO rows
  i$target_month <- "2026-12"
  blockers <- .iov_check_month_consistency(i)
  expect_length(blockers, 1L)
  expect_match(blockers, "2026-12")
})

test_that(".iov_check_weekend_off_cap flags residents over the 2-of-4 limit", {
  r <- fixture_roster()
  # Bosio marks 3 weekends as ferie → violation
  i <- fixture_inputs()
  i$desiderata_long <- tibble::tibble(
    resident = rep("Bosio", 3),
    year = rep("5", 3),
    date = as.Date(c("2026-07-04", "2026-07-11", "2026-07-18")),
    dow = rep("Sab", 3),
    shift = rep("GIORNO", 3),
    status = rep("ferie", 3),
    preference = rep("neutral", 3),
    raw_value = rep("AF", 3)
  )
  warnings <- .iov_check_weekend_off_cap(i, r, threshold = 2L)
  expect_length(warnings, 1L)
  expect_match(warnings, "Bosio")
})

test_that(".iov_check_weekend_off_cap returns empty when all under threshold", {
  r <- fixture_roster()
  i <- fixture_inputs()
  # Only 1 weekend off for Bosio
  i$desiderata_long <- tibble::tibble(
    resident = "Bosio", year = "5",
    date = as.Date("2026-07-04"), dow = "Sab", shift = "GIORNO",
    status = "ferie", preference = "neutral", raw_value = "AF"
  )
  warnings <- .iov_check_weekend_off_cap(i, r, threshold = 2L)
  expect_equal(warnings, character(0))
})

test_that(".iov_check_unknown_year_warning flags unknown years as soft signal", {
  r <- fixture_roster()
  warnings <- .iov_check_unknown_year_warning(r)
  expect_length(warnings, 1L)
})

test_that(".iov_check_prospetto_desiderata_coherence flags ONCO 1 night with no available residents", {
  r <- fixture_roster()
  i <- fixture_inputs()
  # PROSPETTO has Sat Jul 4 as ONCO 1 night, but desiderata has no NOTTE rows.
  warnings <- .iov_check_prospetto_desiderata_coherence(i)
  expect_true(any(grepl("2026-07-04", warnings)))
})

test_that(".iov_check_clinic_only_in_assenze flags Lonardi/Bergamo in assenze", {
  r <- fixture_roster()
  i <- fixture_inputs()
  i$assenze_long <- dplyr::bind_rows(i$assenze_long, tibble::tibble(
    date = as.Date("2026-07-10"), dow = "Ven",
    person = "Lonardi", absence_type = "ferie", slot = "full_day"
  ))
  warnings <- .iov_check_clinic_only_in_assenze(i, r)
  expect_length(warnings, 1L)
  expect_match(warnings, "Lonardi", ignore.case = TRUE)
})

test_that(".iov_check_active_months_mismatch flags residents not active in target month", {
  members_fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_members(members_fixture)

  # The fixture members all have active_months_2026 = "all".
  # Build a roster with BOSIO and PITTARELLO; target month "2026-07".
  # "all" should match anything → no warnings.
  r <- list(
    residents = tibble::tibble(
      last_name = c("BOSIO", "PITTARELLO"),
      first_name = c("Marco", "Andrea"),
      desiderata_name = c("Bosio", "Pittarello"),
      year = c("5", "5"),
      matched = c(TRUE, TRUE),
      ambiguous = c(FALSE, FALSE),
      in_reparto_block = c(FALSE, FALSE)
    ),
    specialists = tibble::tibble(last_name = character(),
      first_name = character(), role = character(),
      primary_group = character(), subgroup_secondary = character(),
      in_guardie_rotation = logical(), fasi_i_eligible = logical(),
      is_clinic_only = logical(), is_full_inpatient = logical()),
    reparto_block = character(),
    clinic_only_attendings = c("LONARDI", "BERGAMO"),
    inpatient_attendings = c("GALIANO", "BOLSHINSKY"),
    juniors_eligible_for_substitution = character(),
    meta = list(target_month = "2026-07", members_count = 11L,
                ambiguous_names = character())
  )
  warnings <- .iov_check_active_months_mismatch(r, members_fixture)
  # "all" matches → no warnings expected
  expect_equal(warnings, character(0))

  # Now patch the fixture in-memory to simulate a real-world value
  # ("Feb;Mar;Apr;May;Jun" — no Jul). Build a custom workbook:
  custom <- tempfile(fileext = ".xlsx")
  wb <- openxlsx2::wb_workbook()$add_worksheet("members")
  wb <- openxlsx2::wb_add_data(wb, sheet = 1, x = data.frame(
    last_name = "BOSIO", first_name = "Marco", role = "Specializzando",
    unit = "ONCO 1", primary_group = NA, subgroup_secondary = NA,
    in_guardie_rotation = "yes", reperibile_fasi_i = "no",
    notes = "", active_months_2026 = "Feb;Mar;Apr;May;Jun",
    stringsAsFactors = FALSE
  ), col_names = TRUE)
  openxlsx2::wb_save(wb, custom, overwrite = TRUE)

  warnings <- .iov_check_active_months_mismatch(r, custom)
  expect_true(any(grepl("BOSIO", warnings)))
  expect_true(any(grepl("Jul", warnings)))
})
