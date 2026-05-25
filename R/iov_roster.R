# IOV Planner — roster derivation.
#
# Combines parsed inputs (from R/iov_parse.R) with the canonical member list
# in `iov/analysis/IOV_MEMBERS.xlsx` to produce the unified `resolved_roster`
# state described in spec §4.2.
#
# Public functions:
#   - derive_roster(parsed_inputs, members_path, reparto_selection)
#   - read_iov_members(path)
#
# All public functions return tibbles or named lists. No package state is
# mutated. All package access is namespace-qualified — no library() calls.
#
# Spec: docs/superpowers/specs/2026-05-21-iov-planner-design.md §4.2.

#' Parse the canonical IOV_MEMBERS workbook.
#'
#' @param path Absolute path to the IOV_MEMBERS xlsx.
#' @return tibble with normalised types (last_name uppercase, yes/no flags
#'   coerced to logical).
#' @export
read_iov_members <- function(path) {
  if (!file.exists(path)) stop("IOV_MEMBERS file not found: ", path)

  raw <- readxl::read_excel(path, sheet = "members")

  yes_no_to_logical <- function(x) {
    toupper(trimws(as.character(x))) == "YES"
  }

  tibble::tibble(
    last_name           = toupper(trimws(as.character(raw$last_name))),
    first_name          = trimws(as.character(raw$first_name)),
    role                = trimws(as.character(raw$role)),
    unit                = trimws(as.character(raw$unit)),
    primary_group       = trimws(as.character(raw$primary_group)),
    subgroup_secondary  = trimws(as.character(raw$subgroup_secondary)),
    in_guardie_rotation = yes_no_to_logical(raw$in_guardie_rotation),
    reperibile_fasi_i   = yes_no_to_logical(raw$reperibile_fasi_i),
    notes               = trimws(as.character(raw$notes)),
    active_months_2026  = trimws(as.character(raw$active_months_2026))
  )
}

#' Normalise a surname for cross-source matching.
#'
#' Uppercase, strip trailing apostrophes (SOLDA' → SOLDA), trim whitespace,
#' collapse multiple internal spaces.
.iov_normalize_name <- function(x) {
  if (length(x) == 0L) return(character(0))
  out <- toupper(trimws(as.character(x)))
  out <- sub("'+$", "", out)
  out <- gsub("\\s+", " ", out)
  out[is.na(x) | nchar(out) == 0L] <- NA_character_
  out
}

#' Cross-reference desiderata residents against the canonical members table.
#'
#' Joins by normalised surname; when a surname appears multiple times in
#' members (e.g. Sartori), disambiguates by the resident's year tag
#' (matched against the `notes` field which contains "(X°)" for ambiguous
#' Sartori entries in IOV_MEMBERS). Marks `ambiguous = TRUE` when year tag
#' cannot disambiguate.
.iov_match_residents <- function(desiderata_residents, members) {
  d <- tibble::tibble(
    desiderata_name = desiderata_residents$resident,
    year            = as.character(desiderata_residents$year),
    norm            = .iov_normalize_name(desiderata_residents$resident)
  )

  m_residents <- dplyr::filter(members, .data$role %in%
    c("Specializzando", "Specializzando (departed)", "Specialista junior"))
  m_residents$norm <- .iov_normalize_name(m_residents$last_name)
  # Year hint from notes: "(X°)" → X
  m_residents$year_hint <- sub(".*\\(([0-9])°\\).*", "\\1", m_residents$notes)
  m_residents$year_hint[m_residents$year_hint == m_residents$notes] <- NA_character_

  resolve_one <- function(name_norm, year) {
    candidates <- m_residents[m_residents$norm == name_norm, , drop = FALSE]
    if (nrow(candidates) == 0L) {
      return(list(last_name = NA_character_, first_name = NA_character_,
                  matched = FALSE, ambiguous = FALSE))
    }
    if (nrow(candidates) == 1L) {
      return(list(last_name = candidates$last_name[1],
                  first_name = candidates$first_name[1],
                  matched = TRUE, ambiguous = FALSE))
    }
    # Multiple candidates — try year disambiguation
    hit <- candidates[!is.na(candidates$year_hint) &
                        candidates$year_hint == year, , drop = FALSE]
    if (nrow(hit) == 1L) {
      return(list(last_name = hit$last_name[1], first_name = hit$first_name[1],
                  matched = TRUE, ambiguous = FALSE))
    }
    # Cannot disambiguate
    list(last_name = NA_character_, first_name = NA_character_,
         matched = FALSE, ambiguous = TRUE)
  }

  resolved <- purrr::map2(d$norm, d$year, resolve_one)
  tibble::tibble(
    desiderata_name     = d$desiderata_name,
    year                = d$year,
    last_name_resolved  = purrr::map_chr(resolved, "last_name"),
    first_name_resolved = purrr::map_chr(resolved, "first_name"),
    matched             = purrr::map_lgl(resolved, "matched"),
    ambiguous           = purrr::map_lgl(resolved, "ambiguous")
  )
}
