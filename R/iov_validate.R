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
