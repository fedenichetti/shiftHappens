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
