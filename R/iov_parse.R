# IOV Planner — input parsers.
#
# Reads the three xlsx files supplied by the caposala (PROSPETTO inter-unit
# night rota, residents' desiderata workbook, attendings' absences) and turns
# them into the `parsed_inputs` state described in spec §4.2.
#
# Public functions:
#   - read_iov_prospetto(path)
#   - read_iov_desiderata_specializzandi(path, sheet)
#   - read_iov_assenze_specialisti(path)
#   - read_iov_inputs(prospetto_path, desiderata_path, assenze_path, target_month)
#
# All public functions return tibbles (or, in the case of read_iov_inputs, a
# named list of tibbles). No package state is mutated. All package access is
# namespace-qualified — no library() calls.
#
# Spec: docs/superpowers/specs/2026-05-21-iov-planner-design.md §4.

# (functions added in subsequent tasks)

#' Parse the inter-unit weekend night rota PROSPETTO workbook.
#'
#' The source workbook is a single sheet (typically "LUGLIO-> SETTEMBRE")
#' containing one section per month, each with a title row + header row +
#' 8-10 data rows (one per weekend day in that month). This function reads
#' all data rows across all sections and returns one tibble.
#'
#' @param path Absolute path to the PROSPETTO xlsx.
#' @return tibble(date, dow, day_unit, night_unit). One row per weekend day.
#' @export
read_iov_prospetto <- function(path) {
  if (!file.exists(path)) stop("PROSPETTO file not found: ", path)

  sheets <- readxl::excel_sheets(path)
  # Single sheet expected; take the first one.
  raw <- readxl::read_excel(path, sheet = sheets[1], col_names = FALSE,
                            .name_repair = "minimal")

  # Identify data rows: col 2 must be coercible to a positive numeric
  # (Excel date serial). Title/header rows have text or NA there.
  col2_num <- suppressWarnings(as.numeric(raw[[2]]))
  data_mask <- !is.na(col2_num) & col2_num > 0

  if (!any(data_mask)) {
    stop("PROSPETTO contains no data rows — sheet structure unexpected")
  }

  dow_map <- c(SABATO = "Sab", DOMENICA = "Dom",
               LUNEDI = "Lun", "LUNEDÌ" = "Lun",
               MARTEDI = "Mar", "MARTEDÌ" = "Mar",
               MERCOLEDI = "Mer", "MERCOLEDÌ" = "Mer",
               GIOVEDI = "Gio", "GIOVEDÌ" = "Gio",
               VENERDI = "Ven", "VENERDÌ" = "Ven")

  out <- tibble::tibble(
    date       = as.Date(col2_num[data_mask], origin = "1899-12-30"),
    dow        = unname(dow_map[toupper(as.character(raw[[1]][data_mask]))]),
    day_unit   = trimws(as.character(raw[[3]][data_mask])),
    night_unit = trimws(as.character(raw[[4]][data_mask]))
  )
  out
}

#' Classify a single cell value from the assenze file.
#'
#' Returns a tibble row with `absence_type` and `slot`. Unknown markers are
#' classified as `"other"` so the planner UI can surface them. Empty / NA
#' cells return NULL (caller filters them out).
.iov_classify_assenza <- function(v) {
  if (is.na(v) || trimws(v) == "") return(NULL)
  vt <- toupper(trimws(v))
  base <- substr(vt, 1, 2)
  slot <- "full_day"
  if (grepl("POMERIGGIO", vt)) slot <- "pomeriggio"
  if (grepl("MATTINO|MATTINA", vt)) slot <- "mattino"

  type <- switch(base,
    AF = "ferie",
    AC = "congresso",
    NO = if (grepl("GUARDIA", vt)) "no_guardia" else if (grepl("REP", vt)) "no_rep" else "other",
    "other"
  )
  list(absence_type = type, slot = slot)
}

#' Parse the attendings' absence workbook.
#'
#' The file has a single sheet (Foglio1) with rows 1-2 = dow + day-number
#' headers, row 3 = SPECIALISTI marker, rows 4-N = attending rows. We stop
#' at the first row whose first cell matches "SPECIALIZZAND" (case-
#' insensitive) — the resident section is parsed by a different module.
#'
#' @param path Absolute path to the assenze xlsx.
#' @param target_month YYYY-MM string used to build absolute dates from the
#'   day-of-month integers in row 2.
#' @return tibble(date, dow, person, absence_type, slot). Empty cells are
#'   dropped; one row per (person, date) absence.
#' @export
read_iov_assenze_specialisti <- function(path, target_month) {
  if (!file.exists(path)) stop("Assenze file not found: ", path)
  if (!grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", target_month)) {
    stop("target_month must be YYYY-MM, got: ", target_month)
  }

  raw <- readxl::read_excel(path, sheet = 1, col_names = FALSE,
                            .name_repair = "minimal")

  # Row 2 holds day-of-month integers in cols 2..N.
  day_row  <- suppressWarnings(as.integer(unlist(raw[2, ])))
  dow_row  <- as.character(unlist(raw[1, ]))
  day_cols <- which(!is.na(day_row) & day_row >= 1L & day_row <= 31L)

  # Find the SPECIALIZZANDI cutoff row.
  col1 <- toupper(as.character(raw[[1]]))
  cutoff <- which(grepl("SPECIALIZZAND", col1))
  end_row <- if (length(cutoff)) min(cutoff) - 1L else nrow(raw)

  # Attending data rows: 4..end_row (skip rows 1,2,3 which are headers/marker).
  out_rows <- list()
  for (r in seq.int(4L, end_row)) {
    person <- trimws(as.character(raw[[1]][r]))
    if (is.na(person) || person == "") next
    for (c in day_cols) {
      cls <- .iov_classify_assenza(as.character(raw[[c]][r]))
      if (is.null(cls)) next
      d <- as.Date(sprintf("%s-%02d", target_month, day_row[c]))
      out_rows[[length(out_rows) + 1L]] <- tibble::tibble(
        date         = d,
        dow          = dow_row[c],
        person       = person,
        absence_type = cls$absence_type,
        slot         = cls$slot
      )
    }
  }

  if (length(out_rows) == 0L) {
    return(tibble::tibble(
      date         = as.Date(character()),
      dow          = character(),
      person       = character(),
      absence_type = character(),
      slot         = character()
    ))
  }
  dplyr::bind_rows(out_rows)
}
