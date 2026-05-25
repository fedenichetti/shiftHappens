# IOV Planner — input validation.
#
# Runs a series of cross-checks on the parsed inputs (from R/iov_parse.R)
# and the resolved roster (from R/iov_roster.R) and returns a structured
# `list(blockers, warnings)`:
#   - blockers: HARD errors that prevent the solver from running. Surfaced
#       in the Shiny validation panel; user must resolve before "Generate"
#       is enabled.
#   - warnings: SOFT issues to surface to the user but allow generation.
#       Logged in the output xlsx metadata sheet.
#
# Public function:
#   - validate_iov_inputs(parsed_inputs, resolved_roster)
#
# All package access is namespace-qualified — no library() calls.
#
# Spec: docs/superpowers/specs/2026-05-21-iov-planner-design.md §5.1 (HARD
# constraints H4, H7) and §5.2 (SOFT constraint S4).

# (functions added in subsequent tasks)

.iov_check_unknown_residents <- function(parsed_inputs, resolved_roster) {
  if (nrow(parsed_inputs$assenze_long) == 0L) return(character(0))
  known <- c(resolved_roster$residents$last_name,
             resolved_roster$specialists$last_name)
  known <- known[!is.na(known)]
  persons_orig <- unique(parsed_inputs$assenze_long$person)
  persons_norm <- .iov_normalize_name(persons_orig)
  is_unknown   <- !persons_norm %in% known
  unknown_orig <- persons_orig[is_unknown & !is.na(persons_norm)]
  if (length(unknown_orig) == 0L) return(character(0))
  sprintf("Persona '%s' nel file assenze non trovata nel roster IOV_MEMBERS",
          unknown_orig)
}

.iov_check_ambiguous_sartori <- function(resolved_roster) {
  amb <- resolved_roster$residents$desiderata_name[
    resolved_roster$residents$ambiguous
  ]
  if (length(amb) == 0L) return(character(0))
  sprintf(
    paste0("Resident '%s' ha cognome ambiguo (es. Sartori) e il tag d'anno ",
           "non basta a disambiguare contro IOV_MEMBERS"),
    amb
  )
}

.iov_check_unknown_years <- function(resolved_roster) {
  unk <- resolved_roster$residents$desiderata_name[
    !is.na(resolved_roster$residents$year) &
      resolved_roster$residents$year == "unknown"
  ]
  if (length(unk) == 0L) return(character(0))
  sprintf(
    paste0("Resident '%s' ha colore di anno non riconosciuto in riga 3 ",
           "del foglio desiderata"),
    unk
  )
}

.iov_check_reparto_validity <- function(resolved_roster) {
  pool <- resolved_roster$residents$last_name
  pool <- pool[!is.na(pool)]
  invalid <- setdiff(resolved_roster$reparto_block, pool)
  if (length(invalid) == 0L) return(character(0))
  sprintf(
    paste0("Nome '%s' selezionato per REPARTO non è un specializzando ",
           "attivo nel roster del mese"),
    invalid
  )
}

.iov_check_month_consistency <- function(parsed_inputs) {
  in_month <- format(parsed_inputs$prospetto$date, "%Y-%m") ==
    parsed_inputs$target_month
  if (any(in_month)) return(character(0))
  sprintf(
    paste0("Il file PROSPETTO non contiene righe per il mese target %s ",
           "(potrebbe essere relativo a un altro trimestre)"),
    parsed_inputs$target_month
  )
}

# ---------------------------------------------------------------------------
# SOFT warning helpers (Task 2.9)
# ---------------------------------------------------------------------------

.iov_check_weekend_off_cap <- function(parsed_inputs, resolved_roster,
                                       threshold = 2L) {
  d <- parsed_inputs$desiderata_long
  if (nrow(d) == 0L) return(character(0))
  weekend <- d[d$dow %in% c("Sab", "Dom") &
                 d$status %in% c("ferie", "congresso", "unavailable_soft"), ,
               drop = FALSE]
  if (nrow(weekend) == 0L) return(character(0))
  per_resident <- dplyr::distinct(weekend, .data$resident, .data$date)
  counts <- dplyr::summarise(
    dplyr::group_by(per_resident, .data$resident),
    n = dplyr::n(), .groups = "drop"
  )
  violations <- counts$resident[counts$n > threshold]
  if (length(violations) == 0L) return(character(0))
  sprintf(
    paste0("Resident '%s' ha più di %d weekend marcati indisponibili ",
           "(soglia raccomandata)"),
    violations, threshold
  )
}

.iov_check_unknown_year_warning <- function(resolved_roster) {
  unk <- resolved_roster$residents$desiderata_name[
    !is.na(resolved_roster$residents$year) &
      resolved_roster$residents$year == "unknown"
  ]
  if (length(unk) == 0L) return(character(0))
  sprintf(
    paste0("Resident '%s' senza tag d'anno: solver lo tratterà come ",
           "ineleggibile a sostituzioni junior"),
    unk
  )
}

.iov_check_prospetto_desiderata_coherence <- function(parsed_inputs) {
  onco1_nights <- parsed_inputs$prospetto$date[
    parsed_inputs$prospetto$night_unit == "ONCOLOGIA 1" &
      format(parsed_inputs$prospetto$date, "%Y-%m") == parsed_inputs$target_month
  ]
  if (length(onco1_nights) == 0L) return(character(0))

  notte <- parsed_inputs$desiderata_long[
    parsed_inputs$desiderata_long$shift == "NOTTE" &
      parsed_inputs$desiderata_long$status %in%
        c("available", "unavailable_soft", "favorite"), ,
    drop = FALSE
  ]
  available_per_date <- dplyr::summarise(
    dplyr::group_by(notte, .data$date),
    n_available = dplyr::n_distinct(.data$resident),
    .groups = "drop"
  )

  warnings <- character(0)
  for (d in onco1_nights) {
    d <- as.Date(d, origin = "1970-01-01")
    n_avail <- sum(available_per_date$n_available[available_per_date$date == d])
    if (n_avail < 2L) {
      warnings <- c(warnings, sprintf(
        paste0("Notte ONCO 1 del %s (PROSPETTO) ha solo %d specializzandi ",
               "disponibili nel desiderata; coppia notte difficile da chiudere"),
        format(d, "%Y-%m-%d"), n_avail
      ))
    }
  }
  warnings
}

.iov_check_clinic_only_in_assenze <- function(parsed_inputs, resolved_roster) {
  if (nrow(parsed_inputs$assenze_long) == 0L) return(character(0))
  persons <- .iov_normalize_name(parsed_inputs$assenze_long$person)
  clinic <- intersect(persons, resolved_roster$clinic_only_attendings)
  if (length(clinic) == 0L) return(character(0))
  sprintf(
    paste0("Attending clinic-only '%s' compare nel file assenze; ",
           "verifica che non sia un errore (clinic-only non fanno guardie)"),
    clinic
  )
}

# Mapping from month number (zero-padded) to English abbreviation used in
# IOV_MEMBERS active_months_2026 field.
.iov_month_abbr <- c(
  "01" = "Jan", "02" = "Feb", "03" = "Mar", "04" = "Apr",
  "05" = "May", "06" = "Jun", "07" = "Jul", "08" = "Aug",
  "09" = "Sep", "10" = "Oct", "11" = "Nov", "12" = "Dec"
)

.iov_check_active_months_mismatch <- function(resolved_roster, members_path) {
  if (is.null(members_path) || !file.exists(members_path)) return(character(0))
  members <- read_iov_members(members_path)
  target_month <- resolved_roster$meta$target_month
  if (is.null(target_month)) return(character(0))
  month_num <- substr(target_month, 6, 7)
  target_abbr <- unname(.iov_month_abbr[month_num])
  if (is.na(target_abbr)) return(character(0))

  pool <- resolved_roster$residents$last_name
  pool <- pool[!is.na(pool)]
  warnings <- character(0)
  for (name in pool) {
    row <- members[members$last_name == name, , drop = FALSE]
    if (nrow(row) == 0L) next  # absent from IOV_MEMBERS — separate concern
    active_str <- row$active_months_2026[1]
    if (is.na(active_str) || active_str == "" || active_str == "all") next
    months_listed <- trimws(strsplit(active_str, ";", fixed = TRUE)[[1]])
    if (!(target_abbr %in% months_listed)) {
      warnings <- c(warnings, sprintf(
        paste0("Resident '%s' non ha %s in active_months_2026 ",
               "(IOV_MEMBERS: '%s'); verifica se IOV_MEMBERS è aggiornato"),
        name, target_abbr, active_str
      ))
    }
  }
  warnings
}

#' Run all input validation checks and return a structured result.
#'
#' Blockers are HARD errors that prevent the solver. Warnings are SOFT
#' issues to surface in the Shiny panel but allow generation.
#'
#' All checks run unconditionally (no early-exit) so the user sees the
#' FULL picture in one pass without fix -> re-validate -> fix iterations.
#'
#' @param parsed_inputs Named list from `read_iov_inputs()`.
#' @param resolved_roster Named list from `derive_roster()`. Must include
#'   `meta$members_path` for the active_months_2026 mismatch check; if
#'   absent or NULL, that check is skipped silently.
#' @return Named list (blockers, warnings). Each is a character vector
#'   (possibly empty) of Italian-language messages.
#' @export
validate_iov_inputs <- function(parsed_inputs, resolved_roster) {
  members_path <- resolved_roster$meta$members_path

  blockers <- c(
    .iov_check_unknown_residents(parsed_inputs, resolved_roster),
    .iov_check_ambiguous_sartori(resolved_roster),
    .iov_check_unknown_years(resolved_roster),
    .iov_check_reparto_validity(resolved_roster),
    .iov_check_month_consistency(parsed_inputs)
  )
  warnings <- c(
    .iov_check_weekend_off_cap(parsed_inputs, resolved_roster, threshold = 2L),
    .iov_check_unknown_year_warning(resolved_roster),
    .iov_check_prospetto_desiderata_coherence(parsed_inputs),
    .iov_check_clinic_only_in_assenze(parsed_inputs, resolved_roster),
    .iov_check_active_months_mismatch(resolved_roster, members_path)
  )
  list(blockers = blockers, warnings = warnings)
}
