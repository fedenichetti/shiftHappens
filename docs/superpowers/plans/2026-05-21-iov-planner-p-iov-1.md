# IOV Planner — Phase P-IOV-1 (Parsers) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `R/iov_parse.R`, the parsing layer for the IOV Planner tab. Three public parsers + one orchestrator turn the three caposala-supplied xlsx files (PROSPETTO inter-unit night rota, residents' desiderata workbook, attendings' absences) into the `parsed_inputs` state described in spec §4.2.

**Architecture:** Pure-logic R module, no Shiny here. Two parsers (`read_iov_prospetto`, `read_iov_assenze_specialisti`) use `readxl::read_excel` since they only need cell values. The third (`read_iov_desiderata_specializzandi`) requires fill colors and shared-string indices, so it uses `openxlsx2::wb_load` and parses cell formatting via the styles manager (port of `iov/analysis/extract_desiderata_07_2026.R`). All four public functions return tibbles or a named list of tibbles. Private helpers prefixed with `.iov_`. TDD throughout — test fixtures built programmatically with `openxlsx2` so we don't ship real patient data inside the package.

**Tech Stack:** R ≥ 4.3, `readxl`, `openxlsx2`, `tibble`, `dplyr`, `tidyr`, `stringr`, `lubridate`, `testthat` (3rd ed.). No new dependencies — every package is already in `renv.lock`.

**Spec reference:** `docs/superpowers/specs/2026-05-21-iov-planner-design.md`. Sections directly load-bearing for this phase: §4.1 (inputs), §4.2 (parsed state), §4.3 (year-color map), §11 (open questions — none HARD-blocking).

**Exploratory script being ported:** `iov/analysis/extract_desiderata_07_2026.R` (proven working end-to-end against the golden file `iov/analysis/desiderata_07_2026.xlsx`).

---

## Conventions Used Throughout This Plan

- **R package style.** Repo follows package layout (`DESCRIPTION`, `R/`, `tests/testthat/`, `inst/extdata/`). Tests run via `Rscript -e 'pkgload::load_all("."); testthat::test_local()'` so `R/` source is loaded into the test environment without going through `R CMD INSTALL`.
- **No `library()` in `R/*.R`.** All package calls qualified (`readxl::read_excel`, `openxlsx2::wb_load`, `dplyr::filter`, etc.). Existing pattern from `R/io_read.R` and other v1 modules.
- **Private helpers** start with `.iov_` and live in the same `R/iov_parse.R` file. Public functions exported via roxygen `@export` tags.
- **Test fixtures** built programmatically inside `tests/testthat/helper-iov-fixtures.R` so the package can be `R CMD check`ed in CI without shipping the real IOV xlsx files. Real-data tests live in `tests/testthat/test-iov-parse-golden.R` and skip when the source files are absent (via `testthat::skip_if_not(file.exists(...))`).
- **Commit style.** Conventional Commits. One commit per task, last step. No Co-Authored-By trailers (project convention).
- **Italian terminology** preserved in user-facing strings and resident/attending surnames; English in code identifiers and comments.

---

## File Structure

Created in this phase:
- `R/iov_parse.R` — public parsers + private helpers (~250 LOC expected).
- `tests/testthat/helper-iov-fixtures.R` — programmatic fixture builders.
- `tests/testthat/test-iov-parse-prospetto.R` — unit tests for PROSPETTO parser.
- `tests/testthat/test-iov-parse-assenze.R` — unit tests for assenze parser.
- `tests/testthat/test-iov-parse-desiderata.R` — unit tests for desiderata parser (synthetic fixtures).
- `tests/testthat/test-iov-parse-golden.R` — integration test against real `iov/` files; skipped if absent.
- `tests/testthat/test-iov-parse-inputs.R` — unit tests for `read_iov_inputs()` orchestrator.

Not modified in this phase: `app.R`, `R/io_read.R`, `R/io_write.R`, generic v1 modules. The IOV layer is additive.

---

## Task 1.1: Set up test fixtures helper

Build a single helper file with two functions: `.make_tiny_prospetto()` writes a 6-row weekend rota for "LUGLIO 2026" + "AGOSTO 2026" sections; `.make_tiny_assenze()` writes a 2-attendings × 5-days minimal absence file; `.make_tiny_desiderata()` writes a 1-sheet workbook with 4 residents (one per year tier 1°-4°), 2 weeks of days including 1 weekend, with controlled cell fills (yellow on 2 cells, year colors on row 3).

These helpers are *only* used by `test-iov-parse-*.R`. They keep tests deterministic and CI-friendly.

**Files:**
- Create: `tests/testthat/helper-iov-fixtures.R`

- [ ] **Step 1: Write the helper file**

```r
# Programmatic fixture builders for iov_parse tests.
# Helpers prefixed `.iov_fx_` so we never collide with src helpers.

.iov_fx_prospetto <- function(path) {
  wb <- openxlsx2::wb_workbook()
  wb$add_worksheet("LUGLIO-> SETTEMBRE")

  # Row 1: title block (cosmetic), Row 2: column headers.
  openxlsx2::wb_add_data(wb, sheet = 1, x = "PROSPETTO GUARDIE 2026 - LUGLIO",
                         dims = "A1", col_names = FALSE)
  headers <- data.frame(
    GIORNO = "GIORNO", DATA = "DATA",
    DIURNO = "GUARDIA 8:00-20:00", NOTTURNO = "GUARDIA 20:00-8:00",
    stringsAsFactors = FALSE
  )
  openxlsx2::wb_add_data(wb, sheet = 1, x = headers, dims = "A2",
                         col_names = FALSE)

  # Data rows: 4 weekend days, Excel date serials for 2026-07-04..05, 11..12.
  # Day 2026-07-04 = Excel serial 46207 (origin 1899-12-30).
  data <- data.frame(
    dow  = c("SABATO", "DOMENICA", "SABATO", "DOMENICA"),
    date = c(46207, 46208, 46214, 46215),
    day  = c("ANESTESTISTA", "ANESTESTISTA", "ANESTESTISTA", "ANESTESTISTA"),
    night = c("ONCOLOGIA 1", "ONCOLOGIA 2", "SENOLOGICA 1", "ONCOLOGIA 1"),
    stringsAsFactors = FALSE
  )
  openxlsx2::wb_add_data(wb, sheet = 1, x = data, dims = "A3",
                         col_names = FALSE)
  openxlsx2::wb_save(wb, path, overwrite = TRUE)
  invisible(path)
}

.iov_fx_assenze <- function(path) {
  wb <- openxlsx2::wb_workbook()
  wb$add_worksheet("Foglio1")
  # Row 1: dow header; Row 2: day numbers; Row 3: "SPECIALISTI"; Rows 4-5: 2 attendings.
  openxlsx2::wb_add_data(wb, sheet = 1,
    x = data.frame(
      A = c(NA, NA, "SPECIALISTI", "Lonardi", "Procaccio"),
      B = c("MER", 1, NA, NA, NA),
      C = c("GIO", 2, NA, "AF", NA),
      D = c("VEN", 3, NA, "AF", "AC"),
      E = c("SAB", 4, NA, NA, "AF pomeriggio"),
      F = c("DOM", 5, NA, NA, "no guardia"),
      stringsAsFactors = FALSE),
    dims = "A1", col_names = FALSE)
  openxlsx2::wb_save(wb, path, overwrite = TRUE)
  invisible(path)
}

.iov_fx_desiderata <- function(path, sheet = "Luglio 2026") {
  wb <- openxlsx2::wb_workbook()
  wb$add_worksheet(sheet)

  # Row 3: 4 resident surnames in cols C..F, each with a year-color fill.
  # Row 4+: days (col A dow, col B day-of-month, cols C..F: empty / X / AF / yellow-X).
  # July 2026: Wed 1 - Sun 5 covers a weekday range + one weekend.
  # Weekend doubled rows: 1st=GIORNO, 2nd=NOTTE.
  rows <- list(
    c(NA, NA, NA, NA, NA, NA),                              # row 1
    c(NA, NA, NA, NA, NA, NA),                              # row 2
    c(NA, NA, "Rossi", "Bianchi", "Verdi", "Neri"),         # row 3 names
    c("Mer", 1, NA, "x", NA, "AF"),                         # row 4: Wed Jul 1
    c("Gio", 2, "AC", NA, "x", NA),                         # row 5: Thu Jul 2
    c("Ven", 3, NA, NA, NA, NA),                            # row 6: Fri Jul 3
    c("Sab", 4, NA, "X", NA, NA),                           # row 7: Sat Jul 4 GIORNO
    c("Sab", 4, NA, NA, "X", NA),                           # row 8: Sat Jul 4 NOTTE
    c("Dom", 5, NA, NA, NA, "AF"),                          # row 9: Sun Jul 5 GIORNO
    c("Dom", 5, NA, NA, NA, "AF")                           # row 10: Sun Jul 5 NOTTE
  )
  for (i in seq_along(rows)) {
    openxlsx2::wb_add_data(wb, sheet = sheet, x = matrix(rows[[i]], nrow = 1),
                           dims = paste0("A", i), col_names = FALSE)
  }

  # Year-color fills on row 3 (Rossi=1°viola, Bianchi=2°verde, Verdi=3°arancio, Neri=4°azzurro).
  openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "C3", color = openxlsx2::wb_color(hex = "FFB4A7D6"))
  openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "D3", color = openxlsx2::wb_color(hex = "FFD9EAD3"))
  openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "E3", color = openxlsx2::wb_color(hex = "FFF6B26B"))
  openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "F3", color = openxlsx2::wb_color(hex = "FF9FC5E8"))

  # Yellow "favorite" fill on 2 cells: row 6 col C (Rossi, Fri Jul 3) and row 9 col D (Bianchi, Sun Jul 5 GIORNO).
  openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "C6", color = openxlsx2::wb_color(hex = "FFFFFF00"))
  openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "D9", color = openxlsx2::wb_color(hex = "FFFFFF00"))

  openxlsx2::wb_save(wb, path, overwrite = TRUE)
  invisible(path)
}
```

- [ ] **Step 2: Verify the helpers load without error**

Run:
```bash
Rscript -e 'pkgload::load_all("."); source("tests/testthat/helper-iov-fixtures.R"); tmp <- tempfile(fileext = ".xlsx"); .iov_fx_desiderata(tmp); cat("ok:", file.exists(tmp), "\n")'
```

Expected: `ok: TRUE`.

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/helper-iov-fixtures.R
git commit -m "test(iov): programmatic xlsx fixtures for parser tests"
```

---

## Task 1.2: Create `R/iov_parse.R` skeleton

Empty module with header comment, file marker, and stub roxygen for the public functions to be filled in. Establishes the file's contract before any code is written.

**Files:**
- Create: `R/iov_parse.R`

- [ ] **Step 1: Write the skeleton**

```r
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
```

- [ ] **Step 2: Verify pkgload picks up the file**

Run:
```bash
Rscript -e 'pkgload::load_all("."); cat("loaded\n")'
```

Expected: `loaded` with no errors (the file is empty of code, so nothing to break).

- [ ] **Step 3: Commit**

```bash
git add R/iov_parse.R
git commit -m "feat(iov): scaffold R/iov_parse.R module"
```

---

## Task 1.3: `read_iov_prospetto()` parser

Parses the inter-unit weekend night rota. Output schema (spec §4.2):

```
tibble(date <Date>, dow <chr>, day_unit <chr>, night_unit <chr>)
```

One row per weekend day. `dow` is normalized to Italian abbreviations (`Sab`, `Dom`). `day_unit` is almost always `"ANESTESTISTA"` (typo preserved from source) but we keep the column for future-proofing. `night_unit` is one of `"ONCOLOGIA 1"`, `"ONCOLOGIA 2"`, `"SENOLOGICA 1"`, `"CHIRURGIA T. MOLLI"`.

The source workbook has multiple month sections in a single sheet (LUGLIO / AGOSTO / SETTEMBRE blocks), each preceded by a title row and a header row. The parser must skip title/header rows by detecting rows where the second column is non-numeric.

**Files:**
- Create: `tests/testthat/test-iov-parse-prospetto.R`
- Modify: `R/iov_parse.R` (append function)

- [ ] **Step 1: Write the failing test**

```r
test_that("read_iov_prospetto parses weekend rows and skips title/header blocks", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_prospetto(fixture)

  out <- read_iov_prospetto(fixture)

  expect_s3_class(out, "tbl_df")
  expect_named(out, c("date", "dow", "day_unit", "night_unit"))
  expect_equal(nrow(out), 4L)
  expect_equal(out$date, as.Date(c("2026-07-04", "2026-07-05",
                                   "2026-07-11", "2026-07-12")))
  expect_equal(out$dow, c("Sab", "Dom", "Sab", "Dom"))
  expect_equal(out$night_unit,
               c("ONCOLOGIA 1", "ONCOLOGIA 2", "SENOLOGICA 1", "ONCOLOGIA 1"))
  expect_true(all(out$day_unit == "ANESTESTISTA"))
})

test_that("read_iov_prospetto errors on missing file", {
  expect_error(read_iov_prospetto("/no/such/file.xlsx"),
               "PROSPETTO file not found")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-prospetto.R")'
```

Expected: FAIL with `could not find function "read_iov_prospetto"`.

- [ ] **Step 3: Write the implementation**

Append to `R/iov_parse.R`:

```r
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
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-prospetto.R")'
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add R/iov_parse.R tests/testthat/test-iov-parse-prospetto.R
git commit -m "feat(iov): read_iov_prospetto parses inter-unit weekend night rota"
```

---

## Task 1.4: `read_iov_assenze_specialisti()` parser

Parses the attendings' absence file (`assenze MM.YYYY.xlsx`, single sheet `Foglio1`). Output schema:

```
tibble(date <Date>, dow <chr>, person <chr>, absence_type <chr>, slot <chr>)
```

`absence_type` is one of `"ferie"` (AF), `"congresso"` (AC), `"no_guardia"`, `"no_rep"`, `"other"`. `slot` is `"full_day"` unless the source cell contained a qualifier like `"AF pomeriggio"`, in which case `slot = "pomeriggio"` (or `"mattino"` if `"AF mattino"`).

The source has rows 1-2 as dow + day-number headers, row 3 = "SPECIALISTI" section marker, rows 4-N = attending names + per-day cells. Row N+1 may contain "SPECIALIZZANDI" — the assenze file mixes both, but this parser is ONLY for attendings (we stop at the residents section header). The target month must be inferred from the file (caller supplies it for cross-validation in `read_iov_inputs`).

**Files:**
- Create: `tests/testthat/test-iov-parse-assenze.R`
- Modify: `R/iov_parse.R` (append function)

- [ ] **Step 1: Write the failing test**

```r
test_that("read_iov_assenze_specialisti parses AF/AC/partial qualifiers", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_assenze(fixture)

  out <- read_iov_assenze_specialisti(fixture, target_month = "2026-07")

  expect_s3_class(out, "tbl_df")
  expect_named(out, c("date", "dow", "person", "absence_type", "slot"))

  # Lonardi: AF Jul 2 + AF Jul 3
  lonardi <- dplyr::filter(out, person == "Lonardi")
  expect_equal(nrow(lonardi), 2L)
  expect_true(all(lonardi$absence_type == "ferie"))
  expect_true(all(lonardi$slot == "full_day"))

  # Procaccio: AC Jul 3 + "AF pomeriggio" Jul 4 + "no guardia" Jul 5
  proc <- dplyr::filter(out, person == "Procaccio")
  expect_equal(nrow(proc), 3L)
  expect_equal(proc$absence_type, c("congresso", "ferie", "no_guardia"))
  expect_equal(proc$slot,         c("full_day", "pomeriggio", "full_day"))
})

test_that("read_iov_assenze_specialisti is case-insensitive (AF, Af, af)", {
  fixture <- tempfile(fileext = ".xlsx")
  wb <- openxlsx2::wb_workbook()
  wb$add_worksheet("Foglio1")
  openxlsx2::wb_add_data(wb, sheet = 1,
    x = data.frame(
      A = c(NA, NA, "SPECIALISTI", "Tester"),
      B = c("MER", 1, NA, "AF"),
      C = c("GIO", 2, NA, "Af"),
      D = c("VEN", 3, NA, "af"),
      stringsAsFactors = FALSE),
    dims = "A1", col_names = FALSE)
  openxlsx2::wb_save(wb, fixture, overwrite = TRUE)

  out <- read_iov_assenze_specialisti(fixture, target_month = "2026-07")
  expect_equal(nrow(out), 3L)
  expect_true(all(out$absence_type == "ferie"))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-assenze.R")'
```

Expected: FAIL with `could not find function "read_iov_assenze_specialisti"`.

- [ ] **Step 3: Write the implementation**

Append to `R/iov_parse.R`:

```r
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
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-assenze.R")'
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add R/iov_parse.R tests/testthat/test-iov-parse-assenze.R
git commit -m "feat(iov): read_iov_assenze_specialisti parses attending absences"
```

---

## Task 1.5: Shared-strings + style-to-fill helpers

Two private helpers that wrap the openxlsx2 machinery for reading cell values that are SST-indexed strings and for resolving a cell style index to its fill RGB. These are reused by the resident roster extractor (Task 1.6) and the cell-level desiderata parser (Task 1.7).

Without these helpers the parsers would have to inline ~30 lines of XML parsing each, which would be unreadable. They are tested directly so any future openxlsx2 upgrade that breaks XML shape gets caught at this layer.

**Files:**
- Create: `tests/testthat/test-iov-parse-desiderata.R` (we'll keep extending it through Tasks 1.5-1.7)
- Modify: `R/iov_parse.R` (append two helpers)

- [ ] **Step 1: Write the failing tests for the helpers**

```r
test_that(".iov_shared_strings decodes <si><t> wrappers", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_desiderata(fixture)
  wb <- openxlsx2::wb_load(fixture)
  ss <- .iov_shared_strings(wb)
  # We injected 4 surnames + day-of-week text — at minimum those should appear.
  expect_true("Rossi" %in% ss)
  expect_true("Bianchi" %in% ss)
})

test_that(".iov_style_to_fill_rgb resolves row-3 fills correctly", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_desiderata(fixture)
  wb <- openxlsx2::wb_load(fixture)
  fill_lookup <- .iov_style_to_fill_rgb_lookup(wb)

  # Row 3 col C (Rossi) was filled FFB4A7D6 (viola → 1°)
  cc <- wb$worksheets[[1]]$sheet_data$cc
  c3 <- cc[cc$c_r == "C3", ]
  expect_true(nrow(c3) >= 1L)
  expect_equal(fill_lookup(c3$c_s[1]), "FFB4A7D6")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-desiderata.R")'
```

Expected: FAIL — both helper functions not defined.

- [ ] **Step 3: Write the helpers**

Append to `R/iov_parse.R`:

```r
#' Decode the shared-strings table of an openxlsx2 workbook.
#'
#' openxlsx2 exposes wb$sharedStrings as a character vector of XML fragments
#' like "<si><t>Bonomi</t></si>" or rich-text "<si><r>…</r></si>". We need
#' the plain text per index (0-based in the SST, 1-based in the returned R
#' vector).
.iov_shared_strings <- function(wb) {
  raw <- wb$sharedStrings
  if (length(raw) == 0L) return(character(0))
  vapply(raw, function(x) {
    if (is.na(x) || x == "") return(NA_character_)
    m <- regmatches(x, gregexpr("<t[^>]*>[^<]*</t>", x))[[1]]
    if (length(m) == 0L) return("")
    paste(vapply(m, function(t) {
      sub("</t>$", "", sub("^<t[^>]*>", "", t))
    }, character(1)), collapse = "")
  }, character(1), USE.NAMES = FALSE)
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

  fill_rgb <- vapply(fills, function(xml) {
    m <- regmatches(xml, regexpr('fgColor rgb="([A-F0-9]+)"', xml))
    if (length(m) == 0L) return(NA_character_)
    sub('"$', "", sub('fgColor rgb="', "", m))
  }, character(1))

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-desiderata.R")'
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add R/iov_parse.R tests/testthat/test-iov-parse-desiderata.R
git commit -m "feat(iov): shared-string + style-to-fill helpers for desiderata parser"
```

---

## Task 1.6: Resident roster extractor (year-from-color)

Private helper `.iov_extract_residents(wb, sheet)` that reads row 3 of the desiderata sheet, returns a tibble `(col, resident, year)`. The year is derived from the row-3 fill RGB via the locked color map (spec §4.3). Unknown fills → `year = "unknown"`. The two trailing "Assegnazione …BOZZA" template columns are filtered out.

**Files:**
- Modify: `R/iov_parse.R` (append helper + year-map constant)
- Modify: `tests/testthat/test-iov-parse-desiderata.R` (append test)

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-iov-parse-desiderata.R`:

```r
test_that(".iov_extract_residents reads row 3 names and derives year from fill", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_desiderata(fixture)
  wb <- openxlsx2::wb_load(fixture)

  res <- .iov_extract_residents(wb, sheet = "Luglio 2026")

  expect_s3_class(res, "tbl_df")
  expect_named(res, c("col", "resident", "year"))
  expect_equal(nrow(res), 4L)
  expect_equal(res$resident, c("Rossi", "Bianchi", "Verdi", "Neri"))
  expect_equal(res$year, c("1", "2", "3", "4"))
})

test_that(".iov_extract_residents drops 'Assegnazione …BOZZA' template cols", {
  fixture <- tempfile(fileext = ".xlsx")
  wb <- openxlsx2::wb_workbook()
  wb$add_worksheet("Test")
  openxlsx2::wb_add_data(wb, sheet = 1,
    x = matrix(c(NA, NA, "Rossi", "Assegnazione guardia BOZZA"),
               nrow = 1),
    dims = "A3", col_names = FALSE)
  openxlsx2::wb_add_fill(wb, sheet = 1, dims = "C3",
                         color = openxlsx2::wb_color(hex = "FFB4A7D6"))
  openxlsx2::wb_save(wb, fixture, overwrite = TRUE)

  wb2 <- openxlsx2::wb_load(fixture)
  res <- .iov_extract_residents(wb2, sheet = "Test")
  expect_equal(nrow(res), 1L)
  expect_equal(res$resident, "Rossi")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-desiderata.R")'
```

Expected: FAIL — `.iov_extract_residents` not defined.

- [ ] **Step 3: Write the year map + extractor**

Append to `R/iov_parse.R`:

```r
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

  r3 <- cc[cc$row_r == "3", , drop = FALSE]
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-desiderata.R")'
```

Expected: 4 tests pass (the 2 helper tests from Task 1.5 + the 2 new ones).

- [ ] **Step 5: Commit**

```bash
git add R/iov_parse.R tests/testthat/test-iov-parse-desiderata.R
git commit -m "feat(iov): extract residents + year from row-3 fill colors"
```

---

## Task 1.7: `read_iov_desiderata_specializzandi()` — full long-format parser

The public function that ties everything together. Output schema (spec §4.2):

```
tibble(date <Date>, dow <chr>, shift <chr>, resident <chr>, year <chr>,
       status <chr>, preference <chr>, raw_value <chr>)
```

For each (resident × date × shift) it emits one row. `shift ∈ {"GIORNO","NOTTE"}`. Convention (locked decision #8): weekend rows duplicated — 1st row = GIORNO, 2nd = NOTTE; weekday rows single, NOTTE only (residents do not work daytime feriale).

`status` values:
- `"available"` — empty cell
- `"unavailable_soft"` — `"X"` or `"x"`
- `"ferie"` — starts with `"AF"`
- `"congresso"` — starts with `"AC"`
- `"other"` — anything else (annotation)

`preference` values:
- `"favorite"` — cell has a yellow fill (one of `FFFFFF00`, `FFFFF2CC`, `FFFFE599`, `FFFFD966`)
- `"neutral"` — otherwise

`target_month` parameter (YYYY-MM) is used to build absolute dates from the day-of-month integers in col B.

**Files:**
- Modify: `R/iov_parse.R` (append public function + yellow-rgb constant)
- Modify: `tests/testthat/test-iov-parse-desiderata.R` (append test)

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-iov-parse-desiderata.R`:

```r
test_that("read_iov_desiderata_specializzandi long-format covers all (resident × date × shift)", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_desiderata(fixture)

  out <- read_iov_desiderata_specializzandi(fixture,
    sheet = "Luglio 2026", target_month = "2026-07")

  expect_s3_class(out, "tbl_df")
  expect_named(out, c("date", "dow", "shift", "resident", "year",
                      "status", "preference", "raw_value"))

  # 4 residents × 7 day-rows (3 weekdays + 2 weekend × 2 rows) = 28 rows.
  expect_equal(nrow(out), 28L)
  expect_equal(sort(unique(out$shift)), c("GIORNO", "NOTTE"))

  # Spot-check: Bianchi on Wed Jul 1 row had "x" → unavailable_soft, NOTTE shift.
  bw1 <- dplyr::filter(out, resident == "Bianchi", date == as.Date("2026-07-01"))
  expect_equal(nrow(bw1), 1L)
  expect_equal(bw1$shift, "NOTTE")
  expect_equal(bw1$status, "unavailable_soft")
  expect_equal(bw1$raw_value, "x")

  # Spot-check: Sat Jul 4 row 7 (seq=1) = GIORNO, row 8 (seq=2) = NOTTE.
  sat <- dplyr::filter(out, date == as.Date("2026-07-04"))
  expect_equal(nrow(sat), 8L)  # 4 residents × 2 shifts
  bianchi_sat <- dplyr::filter(sat, resident == "Bianchi")
  expect_equal(bianchi_sat$status[bianchi_sat$shift == "GIORNO"], "unavailable_soft")
  expect_equal(bianchi_sat$status[bianchi_sat$shift == "NOTTE"], "available")

  # Yellow fill: Rossi Fri Jul 3 (col C row 6) + Bianchi Sun Jul 5 GIORNO (col D row 9).
  fav <- dplyr::filter(out, preference == "favorite")
  expect_equal(nrow(fav), 2L)
  expect_true(all(c("Rossi", "Bianchi") %in% fav$resident))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-desiderata.R")'
```

Expected: FAIL — `read_iov_desiderata_specializzandi` not defined.

- [ ] **Step 3: Write the implementation**

Append to `R/iov_parse.R`:

```r
#' Yellow-fill RGBs that mark a "favorite" (preferred) cell.
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
    dplyr::left_join(day_idx, by = "row") |>
    dplyr::mutate(
      status     = vapply(.data$raw_value, .iov_parse_status, character(1)),
      preference = ifelse(.data$fill_rgb %in% .iov_yellow_rgbs,
                          "favorite", "neutral")
    ) |>
    dplyr::select("date", "dow", "shift", "resident", "year",
                  "status", "preference", "raw_value")

  long
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-desiderata.R")'
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add R/iov_parse.R tests/testthat/test-iov-parse-desiderata.R
git commit -m "feat(iov): read_iov_desiderata_specializzandi long-format parser"
```

---

## Task 1.8: Golden integration test against real `iov/` files

Validates the synthetic-fixture-based unit tests against the real source workbook. Skipped on CI (where the real files aren't present) and run locally to catch fixture drift. Reads `iov/analysis/desiderata_07_2026.xlsx` (the golden output from `extract_desiderata_07_2026.R`) and asserts that `read_iov_desiderata_specializzandi("iov/Turni …xlsx", "Luglio 2026", "2026-07")` produces the same long format for July 2026.

**Files:**
- Create: `tests/testthat/test-iov-parse-golden.R`

- [ ] **Step 1: Write the golden test**

```r
.iov_golden_src_desiderata <- "iov/Turni coguardia + guardia 2026 specializzandi.xlsx"
.iov_golden_out_desiderata <- "iov/analysis/desiderata_07_2026.xlsx"
.iov_golden_src_prospetto  <- "iov/PROSPETTO GUARDIE 2026_LUGLIO_SETTEMBRE_DEF_.xlsx"

test_that("read_iov_desiderata_specializzandi matches the golden derived file", {
  testthat::skip_if_not(file.exists(.iov_golden_src_desiderata),
    "Real IOV desiderata workbook not present — skipping golden test")
  testthat::skip_if_not(file.exists(.iov_golden_out_desiderata),
    "Golden derived file not present — skipping golden test")

  parsed <- read_iov_desiderata_specializzandi(
    .iov_golden_src_desiderata,
    sheet = "Luglio 2026",
    target_month = "2026-07"
  )
  golden <- readxl::read_excel(.iov_golden_out_desiderata,
                               sheet = "desiderata_long")

  # Row counts must match (the golden was generated with the same convention).
  expect_equal(nrow(parsed), nrow(golden))

  # 21 active residents from July roster (memory) should all be present;
  # spot-check 4 of them.
  for (name in c("Bof", "Bivona", "Massa", "Pittarello")) {
    expect_true(name %in% parsed$resident,
                info = paste("missing resident:", name))
  }

  # Year tags for the 4 spot-checks: Bof=4, Bivona=1, Massa=1, Pittarello=5.
  uniq <- dplyr::distinct(parsed, resident, year)
  expect_equal(uniq$year[uniq$resident == "Bof"], "4")
  expect_equal(uniq$year[uniq$resident == "Bivona"], "1")
  expect_equal(uniq$year[uniq$resident == "Massa"], "1")
  expect_equal(uniq$year[uniq$resident == "Pittarello"], "5")

  # 3 weekend ONCO 1 attending-night dates: Sat Jul 4, Sun Jul 12, Sat Jul 25
  # must produce exactly 2 NOTTE rows × N residents each. Just check date set.
  notte_dates <- sort(unique(dplyr::filter(parsed, shift == "NOTTE")$date))
  expect_true(as.Date("2026-07-04") %in% notte_dates)
  expect_true(as.Date("2026-07-12") %in% notte_dates)
  expect_true(as.Date("2026-07-25") %in% notte_dates)
})

test_that("read_iov_prospetto on the real file picks out the 3 ONCO 1 weekend nights for July", {
  testthat::skip_if_not(file.exists(.iov_golden_src_prospetto),
    "Real IOV PROSPETTO not present — skipping golden test")

  pro <- read_iov_prospetto(.iov_golden_src_prospetto)
  jul_onco1 <- pro |>
    dplyr::filter(format(date, "%Y-%m") == "2026-07",
                  night_unit == "ONCOLOGIA 1")
  expect_equal(sort(jul_onco1$date),
               as.Date(c("2026-07-04", "2026-07-12", "2026-07-25")))
})
```

- [ ] **Step 2: Run the golden tests**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-golden.R")'
```

Expected (locally): 2 tests pass. (On CI without the files: 2 tests skipped.)

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/test-iov-parse-golden.R
git commit -m "test(iov): golden integration test against real July 2026 files"
```

---

## Task 1.9: `read_iov_inputs()` orchestrator + month consistency check

Single entry point used by the Shiny tab. Calls all 3 parsers, returns the `parsed_inputs` named list per spec §4.2, and validates that all three inputs agree on the target month (e.g., dates in the desiderata file must lie within the target month; PROSPETTO must contain at least one row in that month; assenze day numbers must be valid for that month).

**Files:**
- Create: `tests/testthat/test-iov-parse-inputs.R`
- Modify: `R/iov_parse.R` (append `read_iov_inputs`)

- [ ] **Step 1: Write the failing test**

```r
test_that("read_iov_inputs combines all 3 parsers and validates month consistency", {
  pro <- tempfile(fileext = ".xlsx")
  des <- tempfile(fileext = ".xlsx")
  ass <- tempfile(fileext = ".xlsx")
  .iov_fx_prospetto(pro)
  .iov_fx_desiderata(des, sheet = "Luglio 2026")
  .iov_fx_assenze(ass)

  out <- read_iov_inputs(
    prospetto_path  = pro,
    desiderata_path = des,
    desiderata_sheet = "Luglio 2026",
    assenze_path    = ass,
    target_month    = "2026-07"
  )

  expect_named(out, c("target_month", "prospetto", "desiderata_long",
                      "assenze_long"))
  expect_equal(out$target_month, "2026-07")
  expect_s3_class(out$prospetto, "tbl_df")
  expect_s3_class(out$desiderata_long, "tbl_df")
  expect_s3_class(out$assenze_long, "tbl_df")

  # PROSPETTO must include at least one row in July 2026.
  expect_true(any(format(out$prospetto$date, "%Y-%m") == "2026-07"))

  # All desiderata dates must lie in July 2026.
  expect_true(all(format(out$desiderata_long$date, "%Y-%m") == "2026-07"))
})

test_that("read_iov_inputs errors when target month has no PROSPETTO rows", {
  pro <- tempfile(fileext = ".xlsx")
  des <- tempfile(fileext = ".xlsx")
  ass <- tempfile(fileext = ".xlsx")
  .iov_fx_prospetto(pro)
  .iov_fx_desiderata(des, sheet = "Luglio 2026")
  .iov_fx_assenze(ass)

  expect_error(
    read_iov_inputs(prospetto_path = pro, desiderata_path = des,
                    desiderata_sheet = "Luglio 2026", assenze_path = ass,
                    target_month = "2026-12"),
    "no PROSPETTO rows for target month"
  )
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-inputs.R")'
```

Expected: FAIL — `read_iov_inputs` not defined.

- [ ] **Step 3: Write the orchestrator**

Append to `R/iov_parse.R`:

```r
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
         " — file may be for a different quarter")
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
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-parse-inputs.R")'
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add R/iov_parse.R tests/testthat/test-iov-parse-inputs.R
git commit -m "feat(iov): read_iov_inputs orchestrator with month consistency check"
```

---

## Task 1.10: Full-suite run + R CMD check + final commit

Verifies nothing in v1 was broken by the IOV additions, that the IOV tests all pass together, and that `R CMD check` is clean.

- [ ] **Step 1: Run the entire test suite**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_local()'
```

Expected: all v1 tests pass (189 + 1 skipped, per memory) plus all new IOV tests pass. No new failures or skips beyond the golden integration test (which may pass locally and skip on CI).

- [ ] **Step 2: Run `R CMD check`**

Run:
```bash
Rscript -e 'devtools::check(args = "--no-manual", quiet = FALSE)'
```

Expected: `0 errors ✓ | 0 warnings ✓ | 0 notes ✓` (matches v1 baseline). If a NOTE about "no visible binding for global variable" appears for `.data`, add `#' @importFrom rlang .data` at the top of `R/iov_parse.R` and re-run.

- [ ] **Step 3: Commit any final fixups (if R CMD check required additions)**

```bash
git add R/iov_parse.R
git commit -m "chore(iov): satisfy R CMD check for iov_parse module"
```

If no fixups were required, skip this step.

---

## Self-Review Pass

Run through this checklist before declaring P-IOV-1 complete:

**Spec coverage:**
- [x] Spec §4.1 inputs (3 workbooks) → covered by Tasks 1.3, 1.4, 1.7
- [x] Spec §4.2 parsed state schema → covered by Task 1.9 (`read_iov_inputs` returns exactly the documented shape, modulo `weekend_attending_nights` which is deferred to P-IOV-2 since it requires roster knowledge)
- [x] Spec §4.3 year-color map → encoded in `.iov_year_map` (Task 1.6) with comment locking it to the spec
- [x] Spec §8 weekend-row convention (1st=GIORNO, 2nd=NOTTE) → encoded in Task 1.7
- [x] Spec §11 open question #1 (ambiguous Sartori) → NOT addressed in P-IOV-1; deferred to roster module (P-IOV-2) where disambiguation logic naturally lives. This is intentional.

**Placeholder scan:** No "TODO" / "add error handling" / "similar to Task N" / undefined references found.

**Type consistency:**
- `read_iov_prospetto` returns `tibble(date, dow, day_unit, night_unit)` — used in Task 1.9 — names match.
- `read_iov_desiderata_specializzandi` returns `tibble(date, dow, shift, resident, year, status, preference, raw_value)` — matches spec §4.2 and Task 1.9 expectations.
- `read_iov_assenze_specialisti` returns `tibble(date, dow, person, absence_type, slot)` — matches spec §4.2.
- All private helpers are referenced in at least one task and defined in the same file.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-21-iov-planner-p-iov-1.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for this phase because parser tasks are independent and each test/implement cycle has a clean verification gate.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints. Best if you want to watch each step live and intervene quickly.

Which approach?
