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
    stop("PROSPETTO contains no data rows -- sheet structure unexpected")
  }

  # Day-name lookup: both unaccented (older xlsx) and accented (I-grave Ì)
  # forms appear in IOV workbooks.  Using \u escapes keeps the file ASCII-safe.
  dow_map <- c(SABATO = "Sab", DOMENICA = "Dom",
               LUNEDI = "Lun", "LUNED\u00cc" = "Lun",
               MARTEDI = "Mar", "MARTED\u00cc" = "Mar",
               MERCOLEDI = "Mer", "MERCOLED\u00cc" = "Mer",
               GIOVEDI = "Gio", "GIOVED\u00cc" = "Gio",
               VENERDI = "Ven", "VENERD\u00cc" = "Ven")

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
#' @param v raw cell value string.
#' @noRd
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
#' like "<si><t>Bonomi</t></si>" or rich-text "<si><r>...</r></si>". We need
#' the plain text per index (0-based in the SST, 1-based in the returned R
#' vector).
#'
#' The returned vector is positionally identical to wb$sharedStrings: entry
#' [i] corresponds to SST index (i - 1L). Duplicates are preserved. Callers
#' that look up cell values by SST index must use direct indexing:
#'   sst[as.integer(v) + 1L]
#' Do NOT deduplicate or filter this vector.
#' @param wb openxlsx2 workbook object.
#' @noRd
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
#' rgb, we walk: cellXfs[c_s+1] -> parse fillId -> fills[fillId+1] -> parse
#' fgColor rgb. We cache the chain into two integer/character vectors and
#' return a fast closure.
#'
#' @param wb openxlsx2 workbook object.
#' @return function(style_idx) -> RGB string ("FFFFFFFF") or NA_character_.
#' @noRd
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

#' Locked year-color map (spec 4.3). Updates require a spec amendment.
#' @noRd
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
#' @param x character vector of column letter strings.
#' @noRd
.iov_col_letter_to_num <- function(x) {
  vapply(x, function(s) {
    if (is.na(s) || s == "") return(NA_integer_)
    chars <- strsplit(s, "")[[1]]
    nums  <- match(chars, LETTERS)
    Reduce(function(a, b) a * 26L + b, nums)
  }, integer(1), USE.NAMES = FALSE)
}

#' Read a single cell's value, honoring shared-string indices.
#' @param c_t cell type attribute from the xlsx cc data frame.
#' @param v raw value attribute.
#' @param is_text inlineStr XML fragment attribute.
#' @param sst shared-strings table returned by .iov_shared_strings.
#' @noRd
.iov_cell_value <- function(c_t, v, is_text, sst) {
  if (!is.na(c_t) && c_t == "e") return(NA_character_)  # error cells => blank
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
#' @param wb openxlsx2 workbook object.
#' @param sheet sheet name string.
#' @noRd
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

#' Yellow-fill RGBs that mark a "favorite" (preferred) cell.
#' @noRd
.iov_yellow_rgbs <- c("FFFFFF00", "FFFFF2CC", "FFFFE599", "FFFFD966")

.iov_parse_status <- function(raw) {
  if (is.na(raw) || trimws(raw) == "") return("available")
  vt <- toupper(trimws(raw))
  if (vt == "X") return("unavailable_soft")
  if (startsWith(vt, "AF")) return("ferie")
  if (startsWith(vt, "AC")) return("congresso")
  "other"
}

#' Parse the residents' desiderata workbook for a given target month.
#'
#' Reads a single sheet (e.g. "Luglio 2026") and returns one row per
#' (resident × date × shift). Weekend rows in the source are duplicated:
#' first = GIORNO (08-20), second = NOTTE (20-08). Weekday rows are single
#' and correspond to NOTTE only (residents do not work daytime feriale).
#'
#' @param path xlsx path.
#' @param sheet Sheet name to parse (e.g. "Luglio 2026").
#' @param target_month YYYY-MM string; the day numbers in column B are
#'   combined with this to build absolute dates.
#' @return tibble(date, dow, shift, resident, year, status, preference, raw_value).
#' @export
read_iov_desiderata_specializzandi <- function(path, sheet, target_month) {
  if (!file.exists(path)) stop("Desiderata file not found: ", path)
  if (!grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", target_month)) {
    stop("target_month must be YYYY-MM, got: ", target_month)
  }

  wb <- openxlsx2::wb_load(path)
  residents <- .iov_extract_residents(wb, sheet)
  if (nrow(residents) == 0L) {
    stop("No residents detected in row 3 of sheet: ", sheet)
  }

  sh  <- which(wb$get_sheet_names() == sheet)
  cc  <- wb$worksheets[[sh]]$sheet_data$cc
  sst <- .iov_shared_strings(wb)
  fill_lookup <- .iov_style_to_fill_rgb_lookup(wb)

  cc$row_int  <- as.integer(cc$row_r)
  cc$col_num  <- .iov_col_letter_to_num(sub("[0-9]+$", "", cc$c_r))

  # Day index: rows 4..N with col B = day-of-month integer.
  day_cells <- cc[cc$col_num == 2L & cc$row_int >= 4L, , drop = FALSE]
  dow_cells <- cc[cc$col_num == 1L & cc$row_int >= 4L, , drop = FALSE]

  day_idx <- tibble::tibble(
    row = day_cells$row_int,
    day = suppressWarnings(as.integer(vapply(seq_len(nrow(day_cells)),
      function(i) .iov_cell_value(day_cells$c_t[i], day_cells$v[i],
                                  day_cells$is[i], sst), character(1)))),
    dow = vapply(seq_len(nrow(dow_cells)),
      function(i) .iov_cell_value(dow_cells$c_t[i], dow_cells$v[i],
                                  dow_cells$is[i], sst), character(1))[
        match(day_cells$row_int, dow_cells$row_int)]
  )
  day_idx <- dplyr::filter(day_idx, !is.na(.data$day))
  day_idx$date <- as.Date(sprintf("%s-%02d", target_month, day_idx$day))

  # Assign shift labels based on weekend-row duplication convention.
  day_idx <- dplyr::arrange(day_idx, .data$row)
  day_idx <- day_idx |>
    dplyr::group_by(.data$date) |>
    dplyr::mutate(
      is_weekend = .data$dow %in% c("Sab", "Dom"),
      seq        = dplyr::row_number(),
      shift      = dplyr::case_when(
        .data$is_weekend & .data$seq == 1 ~ "GIORNO",
        .data$is_weekend & .data$seq == 2 ~ "NOTTE",
        TRUE                              ~ "NOTTE"
      )
    ) |>
    dplyr::ungroup() |>
    dplyr::select("row", "dow", "date", "shift")

  # Data cells: rows >= 4, cols matching residents.
  data_rows <- list()
  for (i in seq_len(nrow(residents))) {
    col_i <- residents$col[i]
    cells_i <- cc[cc$col_num == col_i & cc$row_int >= 4L, , drop = FALSE]
    if (nrow(cells_i) == 0L) {
      # Resident with all-blank column: emit a row per day with status=available.
      data_rows[[length(data_rows) + 1L]] <- tibble::tibble(
        row       = day_idx$row,
        raw_value = NA_character_,
        fill_rgb  = NA_character_,
        resident  = residents$resident[i],
        year      = residents$year[i]
      )
      next
    }
    vals <- vapply(seq_len(nrow(cells_i)),
      function(j) .iov_cell_value(cells_i$c_t[j], cells_i$v[j],
                                  cells_i$is[j], sst), character(1))
    fills <- vapply(cells_i$c_s, fill_lookup, character(1))
    df <- tibble::tibble(
      row = cells_i$row_int,
      raw_value = vals,
      fill_rgb  = fills,
      resident  = residents$resident[i],
      year      = residents$year[i]
    )
    # Add the empty-cell rows (days where the resident has no cell) as available.
    missing_rows <- setdiff(day_idx$row, df$row)
    if (length(missing_rows) > 0L) {
      df <- dplyr::bind_rows(df, tibble::tibble(
        row = missing_rows,
        raw_value = NA_character_,
        fill_rgb  = NA_character_,
        resident  = residents$resident[i],
        year      = residents$year[i]
      ))
    }
    data_rows[[length(data_rows) + 1L]] <- df
  }

  long <- dplyr::bind_rows(data_rows) |>
    dplyr::inner_join(day_idx, by = "row") |>
    dplyr::mutate(
      status     = vapply(.data$raw_value, .iov_parse_status, character(1),
                          USE.NAMES = FALSE),
      preference = ifelse(.data$fill_rgb %in% .iov_yellow_rgbs,
                          "favorite", "neutral")
    ) |>
    dplyr::select("date", "dow", "shift", "resident", "year",
                  "status", "preference", "raw_value")

  long
}

#' Parse all three IOV input workbooks and return the unified parsed_inputs
#' state described in spec §4.2.
#'
#' @param prospetto_path Path to the inter-unit weekend night rota xlsx.
#' @param desiderata_path Path to the residents' desiderata workbook xlsx.
#' @param desiderata_sheet Sheet name within the desiderata workbook
#'   (typically the Italian month name, e.g. "Luglio 2026").
#' @param assenze_path Path to the attendings' absences xlsx.
#' @param target_month YYYY-MM string. All three inputs are cross-validated
#'   against this.
#' @return named list (target_month, prospetto, desiderata_long, assenze_long).
#' @export
read_iov_inputs <- function(prospetto_path, desiderata_path, desiderata_sheet,
                            assenze_path, target_month) {
  if (!grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", target_month)) {
    stop("target_month must be YYYY-MM, got: ", target_month)
  }

  prospetto       <- read_iov_prospetto(prospetto_path)
  desiderata_long <- read_iov_desiderata_specializzandi(
    desiderata_path, sheet = desiderata_sheet, target_month = target_month)
  assenze_long    <- read_iov_assenze_specialisti(
    assenze_path, target_month = target_month)

  # Cross-validation: PROSPETTO must include at least one row in target month.
  in_month <- format(prospetto$date, "%Y-%m") == target_month
  if (!any(in_month)) {
    stop("no PROSPETTO rows for target month ", target_month,
         " -- file may be for a different quarter")
  }

  # Desiderata dates must all lie inside target month (enforced by construction
  # since the parser builds them from target_month). Verify defensively.
  if (nrow(desiderata_long) > 0L &&
      any(format(desiderata_long$date, "%Y-%m") != target_month)) {
    stop("desiderata contains dates outside ", target_month)
  }

  list(
    target_month    = target_month,
    prospetto       = prospetto,
    desiderata_long = desiderata_long,
    assenze_long    = assenze_long
  )
}
