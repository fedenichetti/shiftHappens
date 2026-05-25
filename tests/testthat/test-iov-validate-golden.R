.iov_paths_for_july_v <- function() {
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

test_that("validate_iov_inputs on real July 2026 inputs surfaces known data gaps", {
  p <- .iov_paths_for_july_v()
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

  result <- validate_iov_inputs(parsed, roster)

  # Real IOV_MEMBERS is STALE: missing Jul + missing 4 ex-ONCO2 residents.
  # Expected blockers (known data gaps to fix later by updating IOV_MEMBERS):
  #   - REPARTO validity: BIVONA / BRAVI / BLOISE not in IOV_MEMBERS
  #   - Possibly unknown_residents: people in assenze not in IOV_MEMBERS
  # Therefore blockers > 0 is EXPECTED until IOV_MEMBERS gets updated.
  expect_type(result$blockers, "character")
  expect_type(result$warnings, "character")

  # The REPARTO validity blocker should mention BIVONA/BRAVI/BLOISE explicitly
  reparto_msgs <- result$blockers[grepl("REPARTO", result$blockers)]
  expect_gte(length(reparto_msgs), 1L)

  # Warnings should include the active_months_mismatch (the whole point of
  # adding that check -- most residents don't have "Jul" in IOV_MEMBERS).
  expect_true(any(grepl("active_months_2026", result$warnings)))
})
