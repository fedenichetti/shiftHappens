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

  # IOV_MEMBERS was updated on 2026-05-25 to include "Jul" for the 17 ongoing
  # ONCO 1 residents and to add the 4 ex-ONCO 2 residents (MASSA / BIVONA /
  # BLOISE / BRAVI). After that update we expect:
  #   - REPARTO validity blockers = 0 (all 4 names now resolve in IOV_MEMBERS)
  #   - active_months_mismatch warnings drastically reduced (the 17 ongoing
  #     residents now have Jul in their active_months_2026)
  # Residual blockers/warnings reflect REAL data quality issues (e.g. assenze
  # names not in IOV_MEMBERS at all, weekend off-cap violations).
  expect_type(result$blockers, "character")
  expect_type(result$warnings, "character")

  # All 4 REPARTO names now resolve → no REPARTO validity blockers.
  reparto_msgs <- result$blockers[grepl("REPARTO", result$blockers)]
  expect_equal(length(reparto_msgs), 0L,
    info = paste("Expected 0 REPARTO blockers after IOV_MEMBERS Jul-update;",
                 "got:", paste(reparto_msgs, collapse = " | ")))

  # Weekend off-cap warnings are expected on real data (>2 weekends marked
  # as ferie/X for at least some active residents).
  weekend_cap <- result$warnings[grepl("weekend", result$warnings)]
  expect_gte(length(weekend_cap), 1L)
})
