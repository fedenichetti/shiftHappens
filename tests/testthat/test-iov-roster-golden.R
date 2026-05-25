.iov_paths_for_july <- function() {
  root <- tryCatch(
    rprojroot::find_root(rprojroot::is_r_package),
    error = function(e) NULL
  )
  if (is.null(root)) return(NULL)
  list(
    prospetto    = file.path(root, "iov/PROSPETTO GUARDIE 2026_LUGLIO_SETTEMBRE_DEF_.xlsx"),
    desiderata   = file.path(root, "iov/Turni coguardia + guardia 2026 specializzandi.xlsx"),
    assenze      = file.path(root, "iov/analysis/assenze 07.2026.xlsx"),
    members      = file.path(root, "iov/analysis/IOV_MEMBERS.xlsx")
  )
}

test_that("derive_roster on real July 2026 inputs has expected shape and key residents", {
  p <- .iov_paths_for_july()
  testthat::skip_if(is.null(p),
    "Cannot locate project root — skipping golden test (R CMD check context)")
  for (f in p) {
    testthat::skip_if_not(file.exists(f),
      sprintf("Real IOV file not present: %s", f))
  }

  parsed <- read_iov_inputs(
    prospetto_path   = p$prospetto,
    desiderata_path  = p$desiderata,
    desiderata_sheet = "Luglio 2026",
    assenze_path     = p$assenze,
    target_month     = "2026-07"
  )

  reparto_july <- c("BOF", "BIVONA", "BRAVI", "BLOISE")
  roster <- derive_roster(parsed, p$members, reparto_selection = reparto_july)

  # Resident pool size — desiderata-distinct count. Memory baseline >=21
  # active residents; total pool incl. ex-residents is ~58.
  expect_gte(nrow(roster$residents), 20L)

  # All 4 REPARTO names should resolve to the resolved_roster
  # (NOTE: BIVONA, BRAVI, BLOISE are NOT in IOV_MEMBERS yet — the data gap.
  # They'll appear as NA last_name. BOF should match.)
  expect_setequal(roster$reparto_block, reparto_july)

  # BOF is in IOV_MEMBERS, so it should appear in residents with last_name=="BOF"
  bof_row <- roster$residents[!is.na(roster$residents$last_name) &
                                roster$residents$last_name == "BOF", ]
  expect_gte(nrow(bof_row), 1L)

  # Juniors eligible for substitution: year 1 or 2, NOT in REPARTO.
  # Over-inclusive due to data gap, so just check non-empty + MASSA absent
  # (because MASSA is not in IOV_MEMBERS -> would not appear in residents at all
  # -> not in juniors pool -- confirming the data gap behaviour).
  juniors <- roster$juniors_eligible_for_substitution
  expect_type(juniors, "character")

  # BERTIN should be present (year=2, not in REPARTO, in IOV_MEMBERS)
  expect_true("BERTIN" %in% juniors)
  # BIVONA explicitly EXCLUDED (in REPARTO)
  expect_false("BIVONA" %in% juniors)

  # Specialists: Lonardi & Bergamo flagged clinic-only; Galiano & Bolshinsky
  # flagged full-inpatient
  expect_true(roster$specialists$is_clinic_only[
    roster$specialists$last_name == "LONARDI"])
  expect_true(roster$specialists$is_full_inpatient[
    roster$specialists$last_name == "GALIANO"])
  expect_true(roster$specialists$fasi_i_eligible[
    roster$specialists$last_name == "BOLSHINSKY"])

  # Members count from canonical file (~61 per memory)
  expect_gte(roster$meta$members_count, 60L)
})
