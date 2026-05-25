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
