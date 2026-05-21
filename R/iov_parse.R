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
