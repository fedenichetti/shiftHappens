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

#' Decode the shared-strings table of an openxlsx2 workbook.
#'
#' openxlsx2 exposes wb$sharedStrings as a character vector of XML fragments
#' like "<si><t>Bonomi</t></si>" or rich-text "<si><r>…</r></si>". We need
#' the plain text per index (0-based in the SST, 1-based in the returned R
#' vector).
#'
#' The returned vector is positionally identical to wb$sharedStrings: entry
#' [i] corresponds to SST index (i - 1L). Duplicates are preserved. Callers
#' that look up cell values by SST index must use direct indexing:
#'   sst[as.integer(v) + 1L]
#' Do NOT deduplicate or filter this vector.
.iov_shared_strings <- function(wb) {
  .extract_t_text <- function(x) {
    if (is.na(x) || x == "") return(NA_character_)
    m <- regmatches(x, gregexpr("<t[^>]*>[^<]*</t>", x))[[1]]
    if (length(m) == 0L) return("")
    paste(vapply(m, function(t) {
      sub("</t>$", "", sub("^<t[^>]*>", "", t))
    }, character(1)), collapse = "")
  }

  # Decode every SST entry in order. Length matches wb$sharedStrings exactly.
  vapply(wb$sharedStrings, .extract_t_text, character(1), USE.NAMES = FALSE)
}

#' Build a closure that resolves a cell-style index to its fill RGB string.
#'
#' openxlsx2 represents cellXfs and fills as XML strings inside
#' wb$styles_mgr$styles. To get from a cell's c_s (style index) to its fill
#' rgb, we walk: cellXfs[c_s+1] → parse fillId → fills[fillId+1] → parse
#' fgColor rgb. We cache the chain into two integer/character vectors and
#' return a fast closure.
#'
#' @return function(style_idx) -> RGB string ("FFFFFFFF") or NA_character_.
.iov_style_to_fill_rgb_lookup <- function(wb) {
  cell_xfs <- wb$styles_mgr$styles$cellXfs
  fills    <- wb$styles_mgr$styles$fills

  xf_fillid <- vapply(cell_xfs, function(xml) {
    m <- regmatches(xml, regexpr('fillId="([0-9]+)"', xml))
    if (length(m) == 0L) return(NA_integer_)
    as.integer(sub('fillId="', "", sub('"$', "", m)))
  }, integer(1))

  fill_rgb <- unname(vapply(fills, function(xml) {
    m <- regmatches(xml, regexpr('fgColor rgb="([A-F0-9]+)"', xml))
    if (length(m) == 0L) return(NA_character_)
    sub('"$', "", sub('fgColor rgb="', "", m))
  }, character(1)))

  function(style_idx) {
    if (length(style_idx) == 0L || is.na(style_idx) || style_idx == "") {
      return(NA_character_)
    }
    i <- as.integer(style_idx) + 1L  # cell c_s is 0-based
    if (i < 1L || i > length(xf_fillid)) return(NA_character_)
    fid <- xf_fillid[i]
    if (is.na(fid)) return(NA_character_)
    fill_rgb[fid + 1L]
  }
}

#' Locked year-color map (spec §4.3). Updates require a spec amendment.
.iov_year_map <- c(
  # Reds → ex-resident (not in rotation)
  "FFFF0000" = "0", "FF980000" = "0", "FFE06666" = "0",
  # Pinks → 5° anno (rosa)
  "FFF4CCCC" = "5", "FFEAD1DC" = "5",
  # Blues → 4° anno (azzurro)
  "FF9FC5E8" = "4", "FFCFE2F3" = "4", "FFC9DAF8" = "4", "FFA4C2F4" = "4",
  # Oranges → 3° anno (arancio)
  "FFF6B26B" = "3", "FFF9CB9C" = "3", "FFFCE5CD" = "3",
  # Greens → 2° anno (verde)
  "FFD9EAD3" = "2", "FF93C47D" = "2", "FFB6D7A8" = "2",
  # Purples → 1° anno (viola)
  "FFB4A7D6" = "1", "FFD9D2E9" = "1"
)

.iov_year_for_rgb <- function(rgb) {
  out <- unname(.iov_year_map[rgb])
  ifelse(is.na(out), "unknown", out)
}

#' Convert Excel column letters ("A", "AA") to 1-based numeric indices.
.iov_col_letter_to_num <- function(x) {
  vapply(x, function(s) {
    if (is.na(s) || s == "") return(NA_integer_)
    chars <- strsplit(s, "")[[1]]
    nums  <- match(chars, LETTERS)
    Reduce(function(a, b) a * 26L + b, nums)
  }, integer(1), USE.NAMES = FALSE)
}

#' Read a single cell's value, honoring shared-string indices.
.iov_cell_value <- function(c_t, v, is_text, sst) {
  if (!is.na(c_t) && c_t == "s") {
    idx <- suppressWarnings(as.integer(v))
    if (is.na(idx) || idx + 1L > length(sst)) return(NA_character_)
    sst[idx + 1L]
  } else if (!is.na(c_t) && c_t == "inlineStr") {
    m <- regmatches(is_text, regexpr("<t[^>]*>([^<]*)</t>", is_text))
    if (length(m) == 0L) NA_character_
    else sub("</t>$", "", sub("^<t[^>]*>", "", m))
  } else if (!is.na(v) && v != "") {
    v
  } else NA_character_
}

#' Read row 3 of a desiderata sheet and derive resident year from fill color.
.iov_extract_residents <- function(wb, sheet) {
  sh <- which(wb$get_sheet_names() == sheet)
  if (length(sh) == 0L) stop("Sheet not found: ", sheet)
  cc <- wb$worksheets[[sh]]$sheet_data$cc
  sst <- .iov_shared_strings(wb)
  fill_lookup <- .iov_style_to_fill_rgb_lookup(wb)

  r3 <- cc[as.character(cc$row_r) == "3", , drop = FALSE]
  if (nrow(r3) == 0L) {
    return(tibble::tibble(col = integer(), resident = character(), year = character()))
  }
  r3$col_num <- .iov_col_letter_to_num(sub("[0-9]+$", "", r3$c_r))

  values <- vapply(seq_len(nrow(r3)), function(i) {
    .iov_cell_value(r3$c_t[i], r3$v[i], r3$is[i], sst)
  }, character(1))
  fills <- vapply(r3$c_s, fill_lookup, character(1))

  out <- tibble::tibble(
    col = r3$col_num, resident = values, fill_rgb = fills
  )
  out <- dplyr::filter(out, !is.na(.data$resident), .data$col >= 3L)
  out <- dplyr::filter(out, !grepl("Assegnazione", .data$resident,
                                   ignore.case = TRUE))
  out$year <- .iov_year_for_rgb(out$fill_rgb)
  dplyr::select(out, "col", "resident", "year")
}
