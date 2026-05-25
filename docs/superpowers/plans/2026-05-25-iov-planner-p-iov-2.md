# IOV Planner — Phase P-IOV-2 (Roster + Validation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the IOV roster derivation + input-validation layer on top of P-IOV-1 parsers. `derive_roster(parsed_inputs, members_path, reparto_selection)` produces the unified `resolved_roster` state described in spec §4.2; `validate_iov_inputs(parsed_inputs, resolved_roster)` produces a structured `list(blockers, warnings)` consumed by the future Shiny validation panel and by the solver gatekeeper.

**Architecture:** Two pure-logic R modules (`R/iov_roster.R`, `R/iov_validate.R`) with namespace-qualified package calls. Roster module loads `iov/analysis/IOV_MEMBERS.xlsx` via `readxl`, cross-references resident names from `parsed_inputs$desiderata_long` against the canonical member list (handles apostrophe drift like `SOLDA'`/`SOLDA`, ambiguous Sartori disambiguated by year tag), partitions attendings into `clinic_only` / `full_inpatient` / general pool, and exposes manual REPARTO selection as a parameter. Validation module returns two character vectors: HARD blockers prevent the solver from running; SOFT warnings surface to the user but allow generation. All functions tested with `testthat` against programmatic fixtures + a golden integration test against the real `iov/` workbooks.

**Tech Stack:** R ≥ 4.3, `readxl`, `tibble`, `dplyr`, `stringr`, `purrr`, `lubridate`, `testthat` (3rd ed.). No new dependencies — all are already in `renv.lock`.

**Spec reference:** `docs/superpowers/specs/2026-05-21-iov-planner-design.md`. Sections directly load-bearing:
- §3.1 module map mentions `R/iov_roster.R` + `R/iov_validate.R`.
- §4.2 `resolved_roster` shape: residents / specialists / reparto_block / clinic_only_attendings / inpatient_attendings.
- §5.1 hard constraints H4 (REPARTO block) and H7 (clinic-only attendings ineligibility).
- §5.2 soft constraint S4 (weekend availability cap > 2 of 4 weekends).

**Predecessor commit:** `9fe318a` on `feat/iov-planner` (P-IOV-1 parsers). `read_iov_inputs()` produces `list(target_month, prospetto, desiderata_long, assenze_long)` which is the INPUT to every P-IOV-2 function.

**Project-level facts from memory (golden reference for tests):**
- July 2026 active resident roster (21): ALAM, BASOLI, BERTIN, BIONDI, BOF, BONELLO, BOSA, BOSIO, DAL CENGIO, DI MARCO, DI PAOLO, GAIANI, LEOTTA, PITTARELLO, RONCHI, SARUBBI, SPEROTTO, BIVONA, BLOISE, BRAVI, MASSA.
- REPARTO July 2026 (manual selection): BOF (4°), BIVONA (1°), BRAVI (1°), BLOISE (1°). Pool shrinks 21 → 17.
- Junior-eligible-for-substitution (year ∈ {1,2}, NOT in REPARTO): MASSA, BERTIN, BIONDI, BONELLO, DAL CENGIO, SARUBBI = 6 names.
- Clinic-only attendings (always): LONARDI, BERGAMO.
- Full-inpatient attendings (always): GALIANO, BOLSHINSKY.
- Ambiguous surnames: Sartori (Beatrice = 5° → `sartori_b`, Elena = 1° → `sartori_e`).

---

## Conventions Used Throughout This Plan

- **R package style.** Repo follows package layout. Tests run via `Rscript -e 'pkgload::load_all("."); testthat::test_local()'`.
- **No `library()` in `R/*.R` or test helpers.** All package access namespace-qualified (`readxl::read_excel`, `dplyr::filter`, `stringr::str_detect`).
- **Private helpers** start with `.iov_` and live in the same module file they support. Public functions get `@export` roxygen tags.
- **Test fixtures** programmatic (built via openxlsx2 in `tests/testthat/helper-iov-fixtures.R`). Real-data golden tests skip via `testthat::skip_if_not(file.exists(...))`.
- **Commit style.** Conventional Commits. One commit per task (last step). **No `Co-Authored-By` trailers** — project convention.
- **TDD discipline.** Every task writes failing test → verifies failure → writes minimal impl → verifies pass → commits. Don't skip the "verify failure" step; it confirms the test is real.
- **Italian preserved** in user-facing strings and resident/attending surnames; English in code identifiers and comments.

---

## File Structure

Created in this phase:
- `R/iov_roster.R` — public `derive_roster()` + `read_iov_members()` + private helpers (~200 LOC expected).
- `R/iov_validate.R` — public `validate_iov_inputs()` + 9 private check functions (~180 LOC expected).
- `tests/testthat/test-iov-roster.R` — unit tests with programmatic fixtures.
- `tests/testthat/test-iov-validate.R` — unit tests with programmatic fixtures.
- `tests/testthat/test-iov-roster-golden.R` — integration test against real iov/ files (skip when absent).
- `tests/testthat/test-iov-validate-golden.R` — integration test against real iov/ files (skip when absent).
- `tests/testthat/helper-iov-fixtures.R` — extended with `.iov_fx_members()`.

Not modified in this phase: `R/iov_parse.R`, `R/io_read.R`, `app.R`, generic v1 modules.

---

## Task 2.1: Extend test fixtures helper with `.iov_fx_members()`

The roster module needs a controlled IOV_MEMBERS workbook for unit tests. Build it programmatically with openxlsx2 — covers all attendings categories (Direttrice, Specialista, clinic-only, full-inpatient) plus 4 residents across years (including one ambiguous Sartori pair).

**Files:**
- Modify: `tests/testthat/helper-iov-fixtures.R` (append one new helper)

- [ ] **Step 1: Append the new helper**

Append at the end of `tests/testthat/helper-iov-fixtures.R`:

```r
.iov_fx_members <- function(path) {
  wb <- openxlsx2::wb_workbook()$add_worksheet("members")
  members <- data.frame(
    last_name           = c("LONARDI", "BERGAMO", "GALIANO", "BOLSHINSKY",
                            "PROCACCIO", "NICHETTI",
                            "BOSIO", "PITTARELLO", "MASSA", "SARTORI", "SARTORI"),
    first_name          = c("Sara", "Francesca", "Antonella", "Yulia",
                            "Giorgio", "Federico",
                            "Marco", "Andrea", "Elena", "Beatrice", "Elena"),
    role                = c("Direttrice", "Specialista", "Specialista", "Specialista",
                            "Specialista", "Specialista",
                            "Specializzando", "Specializzando", "Specializzando",
                            "Specializzando", "Specializzando"),
    unit                = rep("ONCO 1", 11),
    primary_group       = c("Direzione", "GASTROENTERICO", "REPARTO", "REPARTO",
                            "GASTROENTERICO", "GASTROENTERICO",
                            NA, NA, NA, NA, NA),
    subgroup_secondary  = c(NA, "Colon", NA, "Phase-I",
                            "Pancreas", "Pancreas",
                            NA, NA, NA, NA, NA),
    in_guardie_rotation = c("no", "no", "no", "no",
                            "yes", "yes",
                            "yes", "yes", "yes", "yes", "yes"),
    reperibile_fasi_i   = c("no", "no", "no", "yes",
                            "no", "yes",
                            "no", "no", "no", "no", "no"),
    notes               = c("clinic-only direttrice", "clinic-only",
                            "full-inpatient", "full-inpatient phase-I",
                            "", "", "", "", "", "Beatrice (5°)", "Elena (1°)"),
    active_months_2026  = rep("all", 11),
    stringsAsFactors    = FALSE
  )
  wb <- openxlsx2::wb_add_data(wb, sheet = 1, x = members, dims = "A1",
                                col_names = TRUE)
  openxlsx2::wb_save(wb, path, overwrite = TRUE)
  invisible(path)
}
```

- [ ] **Step 2: Verify the helper produces a readable workbook**

Run:
```bash
Rscript -e 'pkgload::load_all("."); source("tests/testthat/helper-iov-fixtures.R"); tmp <- tempfile(fileext = ".xlsx"); .iov_fx_members(tmp); m <- readxl::read_excel(tmp); cat("rows:", nrow(m), "cols:", ncol(m), "\n"); print(table(m$in_guardie_rotation, useNA = "always"))'
```

Expected: `rows: 11 cols: 10` and a contingency table showing `no = 4`, `yes = 7`.

- [ ] **Step 3: Commit**

```bash
git add tests/testthat/helper-iov-fixtures.R
git commit -m "test(iov): add .iov_fx_members fixture for roster tests"
```

---

## Task 2.2: Scaffold `R/iov_roster.R`

Empty module with header comment listing the public functions to be filled in.

**Files:**
- Create: `R/iov_roster.R`

- [ ] **Step 1: Write the skeleton**

```r
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

# (functions added in subsequent tasks)
```

- [ ] **Step 2: Verify pkgload picks up the file**

Run:
```bash
Rscript -e 'pkgload::load_all("."); cat("loaded\n")'
```

Expected: `loaded` with no errors.

- [ ] **Step 3: Commit**

```bash
git add R/iov_roster.R
git commit -m "feat(iov): scaffold R/iov_roster.R module"
```

---

## Task 2.3: `read_iov_members(path)` parser

Reads `iov/analysis/IOV_MEMBERS.xlsx` (the canonical roster) into a normalized tibble with consistent types. All `last_name` values are forced UPPERCASE (the source file already follows this convention, but normalize defensively). `in_guardie_rotation` and `reperibile_fasi_i` are coerced to logical (`"yes"` → TRUE, `"no"` → FALSE, `"-"` → FALSE).

**Files:**
- Create: `tests/testthat/test-iov-roster.R`
- Modify: `R/iov_roster.R` (append function)

- [ ] **Step 1: Write the failing test**

```r
test_that("read_iov_members loads canonical member list with normalised types", {
  fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_members(fixture)

  m <- read_iov_members(fixture)

  expect_s3_class(m, "tbl_df")
  expect_true(all(c("last_name", "first_name", "role", "unit",
                    "primary_group", "in_guardie_rotation",
                    "reperibile_fasi_i") %in% names(m)))
  expect_equal(nrow(m), 11L)

  # Logical coercion: in_guardie_rotation
  expect_type(m$in_guardie_rotation, "logical")
  expect_equal(sum(m$in_guardie_rotation), 7L)
  expect_equal(sum(!m$in_guardie_rotation), 4L)

  # Logical coercion: reperibile_fasi_i
  expect_type(m$reperibile_fasi_i, "logical")
  expect_true(m$reperibile_fasi_i[m$last_name == "BOLSHINSKY"])
  expect_false(m$reperibile_fasi_i[m$last_name == "LONARDI"])

  # Uppercase enforcement on last_name
  expect_true(all(m$last_name == toupper(m$last_name)))
})

test_that("read_iov_members errors on missing file", {
  expect_error(read_iov_members("/no/such/file.xlsx"),
               "IOV_MEMBERS file not found")
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-roster.R")'
```

Expected: FAIL with `could not find function "read_iov_members"`.

- [ ] **Step 3: Write the implementation**

Append to `R/iov_roster.R`:

```r
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
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-roster.R")'
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add R/iov_roster.R tests/testthat/test-iov-roster.R
git commit -m "feat(iov): read_iov_members parses canonical member list"
```

---

## Task 2.4: `.iov_normalize_name()` private helper

Normalize surnames for matching across the desiderata file (`Bosio`, `Solda'`) and IOV_MEMBERS (`BOSIO`, `SOLDA`). Rules:
1. Uppercase.
2. Strip trailing apostrophes (handles SOLDA' / SOLDA, TROVO' / TROVO).
3. Strip leading/trailing whitespace.
4. Replace internal multiple whitespace with single space (handles "Di  Marco").

This helper is shared between roster matching and validation.

**Files:**
- Modify: `R/iov_roster.R` (append helper)
- Modify: `tests/testthat/test-iov-roster.R` (append test)

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-iov-roster.R`:

```r
test_that(".iov_normalize_name handles apostrophe drift and casing", {
  expect_equal(.iov_normalize_name("Solda'"),  "SOLDA")
  expect_equal(.iov_normalize_name("SOLDA"),    "SOLDA")
  expect_equal(.iov_normalize_name("Trovò"),   "TROVÒ")
  expect_equal(.iov_normalize_name("Trovò'"),  "TROVÒ")
  expect_equal(.iov_normalize_name("Di Marco"), "DI MARCO")
  expect_equal(.iov_normalize_name("  Bosio "), "BOSIO")
  expect_equal(.iov_normalize_name("Di  Marco"), "DI MARCO")  # double space
  expect_true(is.na(.iov_normalize_name(NA_character_)))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-roster.R")'
```

Expected: FAIL with `could not find function ".iov_normalize_name"`.

- [ ] **Step 3: Write the implementation**

Append to `R/iov_roster.R`:

```r
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
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-roster.R")'
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add R/iov_roster.R tests/testthat/test-iov-roster.R
git commit -m "feat(iov): .iov_normalize_name handles apostrophe drift"
```

---

## Task 2.5: `.iov_match_residents()` private helper

Cross-references resident names from `parsed_inputs$desiderata_long` against the canonical `members` table. Returns a tibble with one row per UNIQUE desiderata resident plus their resolved member metadata. Handles two name-quirk cases explicitly:
- Apostrophe drift via `.iov_normalize_name()`.
- Ambiguous Sartori: two Sartoris in members (Beatrice 5° and Elena 1°). The desiderata file lists "Sartori" twice (once year=2, once year=1 — see P-IOV-1 golden test). Match by `(normalized_name, year)` pair: Sartori+year=5 → SARTORI Beatrice; Sartori+year=1 → SARTORI Elena. If a desiderata Sartori has year that doesn't match any member, flag in `ambiguous` column = TRUE.

**Files:**
- Modify: `R/iov_roster.R` (append helper)
- Modify: `tests/testthat/test-iov-roster.R` (append test)

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-iov-roster.R`:

```r
test_that(".iov_match_residents joins by normalised surname + year", {
  members <- tibble::tibble(
    last_name = c("BOSIO", "MASSA", "SARTORI", "SARTORI"),
    first_name = c("Marco", "Elena", "Beatrice", "Elena"),
    role = rep("Specializzando", 4),
    in_guardie_rotation = rep(TRUE, 4),
    primary_group = NA_character_, subgroup_secondary = NA_character_,
    reperibile_fasi_i = rep(FALSE, 4), notes = c("", "", "Beatrice (5°)", "Elena (1°)"),
    unit = rep("ONCO 1", 4), active_months_2026 = rep("all", 4)
  )
  desiderata_residents <- tibble::tibble(
    resident = c("Bosio", "Massa", "Sartori", "Sartori"),
    year     = c("5",     "1",     "5",       "1")
  )

  out <- .iov_match_residents(desiderata_residents, members)

  expect_s3_class(out, "tbl_df")
  expect_named(out, c("desiderata_name", "year", "last_name_resolved",
                      "first_name_resolved", "matched", "ambiguous"))
  expect_equal(nrow(out), 4L)
  expect_true(all(out$matched))
  expect_false(any(out$ambiguous))

  # Sartori year=5 → Beatrice; Sartori year=1 → Elena
  sartori_5 <- out[out$desiderata_name == "Sartori" & out$year == "5", ]
  expect_equal(sartori_5$first_name_resolved, "Beatrice")
  sartori_1 <- out[out$desiderata_name == "Sartori" & out$year == "1", ]
  expect_equal(sartori_1$first_name_resolved, "Elena")
})

test_that(".iov_match_residents flags ambiguous when year doesn't disambiguate", {
  members <- tibble::tibble(
    last_name = c("SARTORI", "SARTORI"),
    first_name = c("Beatrice", "Elena"),
    role = rep("Specializzando", 2), in_guardie_rotation = rep(TRUE, 2),
    primary_group = NA_character_, subgroup_secondary = NA_character_,
    reperibile_fasi_i = rep(FALSE, 2), notes = c("Beatrice (5°)", "Elena (1°)"),
    unit = rep("ONCO 1", 2), active_months_2026 = rep("all", 2)
  )
  # Desiderata Sartori with year="unknown" — neither Beatrice nor Elena.
  desiderata_residents <- tibble::tibble(
    resident = "Sartori", year = "unknown"
  )

  out <- .iov_match_residents(desiderata_residents, members)
  expect_equal(nrow(out), 1L)
  expect_false(out$matched)
  expect_true(out$ambiguous)
  expect_true(is.na(out$last_name_resolved))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-roster.R")'
```

Expected: FAIL with `could not find function ".iov_match_residents"`.

- [ ] **Step 3: Write the implementation**

Append to `R/iov_roster.R`:

```r
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
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-roster.R")'
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add R/iov_roster.R tests/testthat/test-iov-roster.R
git commit -m "feat(iov): .iov_match_residents disambiguates Sartori by year"
```

---

## Task 2.6: `derive_roster()` public orchestrator

Combines `parsed_inputs` + `members` + manual REPARTO selection into the unified `resolved_roster` named list per spec §4.2. The list is structured for direct consumption by the future MILP model (P-IOV-3) and Shiny validation panel (P-LAND-3).

Constants (clinic-only + full-inpatient) are NOT read from IOV_MEMBERS columns (the column is the rotation flag, not a classification); instead they're hard-coded sets at the top of `R/iov_roster.R` so they're discoverable and amendable in one place. This matches the spec §3.1 "Locked decisions table" where these four names are called out by name.

**Files:**
- Modify: `R/iov_roster.R` (append constants + `derive_roster`)
- Modify: `tests/testthat/test-iov-roster.R` (append test)

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-iov-roster.R`:

```r
test_that("derive_roster builds the resolved_roster list with REPARTO + pools", {
  members_fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_members(members_fixture)

  # Synthetic parsed_inputs covering 4 residents from the members fixture
  # (BOSIO 5°, PITTARELLO 5°, MASSA 1°, SARTORI Elena 1°)
  desiderata_long <- tibble::tibble(
    resident = c("Bosio", "Pittarello", "Massa", "Sartori"),
    year     = c("5",     "5",          "1",     "1"),
    date     = as.Date(rep("2026-07-04", 4)),
    dow = "Sab", shift = "GIORNO", status = "available",
    preference = "neutral", raw_value = NA_character_
  )
  parsed_inputs <- list(
    target_month    = "2026-07",
    prospetto       = tibble::tibble(date = as.Date("2026-07-04"), dow = "Sab",
                                     day_unit = "ANESTESTISTA",
                                     night_unit = "ONCOLOGIA 1"),
    desiderata_long = desiderata_long,
    assenze_long    = tibble::tibble(date = as.Date(character()),
                                     dow = character(), person = character(),
                                     absence_type = character(), slot = character())
  )

  roster <- derive_roster(parsed_inputs, members_fixture,
                          reparto_selection = c("MASSA", "BOSIO"))

  expect_named(roster, c("residents", "specialists", "reparto_block",
                         "clinic_only_attendings", "inpatient_attendings",
                         "juniors_eligible_for_substitution", "meta"))

  # Residents tibble
  expect_s3_class(roster$residents, "tbl_df")
  expect_equal(nrow(roster$residents), 4L)
  expect_true(all(c("BOSIO", "PITTARELLO", "MASSA", "SARTORI") %in%
                    roster$residents$last_name))

  # REPARTO membership flag
  expect_setequal(
    roster$residents$last_name[roster$residents$in_reparto_block],
    c("MASSA", "BOSIO")
  )

  # Specialists tibble — must include Lonardi, Bergamo, Galiano, Bolshinsky,
  # Procaccio, Nichetti from the members fixture
  expect_true(all(c("LONARDI", "BERGAMO", "GALIANO", "BOLSHINSKY",
                    "PROCACCIO", "NICHETTI") %in% roster$specialists$last_name))
  expect_true(roster$specialists$is_clinic_only[
    roster$specialists$last_name == "LONARDI"])
  expect_true(roster$specialists$is_full_inpatient[
    roster$specialists$last_name == "GALIANO"])
  expect_true(roster$specialists$fasi_i_eligible[
    roster$specialists$last_name == "BOLSHINSKY"])

  # Constant pools
  expect_setequal(roster$clinic_only_attendings, c("LONARDI", "BERGAMO"))
  expect_setequal(roster$inpatient_attendings,   c("GALIANO", "BOLSHINSKY"))
  expect_setequal(roster$reparto_block,          c("MASSA", "BOSIO"))

  # Juniors eligible for substitution = year 1 or 2, NOT in REPARTO.
  # MASSA is in REPARTO so excluded; SARTORI year=1 stays. (PITTARELLO 5°, BOSIO 5° excluded by year.)
  expect_setequal(roster$juniors_eligible_for_substitution, "SARTORI")

  # Meta
  expect_equal(roster$meta$target_month, "2026-07")
  expect_equal(roster$meta$members_count, 11L)
})

test_that("derive_roster errors when reparto_selection has < 4 names (memo: July has exactly 4)", {
  # Note: spec doesn't enforce exactly 4 (size depends on month); we only
  # require non-empty selection if MILP is to apply H4 — but validation lives
  # in validate_iov_inputs(). derive_roster accepts any vector ≥ 0.
  members_fixture <- tempfile(fileext = ".xlsx")
  .iov_fx_members(members_fixture)
  parsed_inputs <- list(
    target_month = "2026-07",
    prospetto = tibble::tibble(date = as.Date("2026-07-04"), dow = "Sab",
                               day_unit = "X", night_unit = "X"),
    desiderata_long = tibble::tibble(
      resident = "Bosio", year = "5", date = as.Date("2026-07-01"),
      dow = "Mer", shift = "NOTTE", status = "available",
      preference = "neutral", raw_value = NA_character_
    ),
    assenze_long = tibble::tibble(date = as.Date(character()),
                                  dow = character(), person = character(),
                                  absence_type = character(), slot = character())
  )
  out <- derive_roster(parsed_inputs, members_fixture,
                       reparto_selection = character())
  expect_equal(length(out$reparto_block), 0L)
  expect_equal(length(out$juniors_eligible_for_substitution),
               0L)  # no juniors in this synthetic input
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-roster.R")'
```

Expected: FAIL with `could not find function "derive_roster"`.

- [ ] **Step 3: Write the implementation**

Append to `R/iov_roster.R`:

```r
#' Constants — clinic-only and full-inpatient attending sets (spec §3.1).
#' Changing these requires a spec amendment.
.iov_clinic_only_attendings <- c("LONARDI", "BERGAMO")
.iov_inpatient_attendings   <- c("GALIANO", "BOLSHINSKY")

#' Build the unified resolved_roster from parsed inputs + members + REPARTO.
#'
#' @param parsed_inputs Named list from `read_iov_inputs()`.
#' @param members_path Absolute path to `IOV_MEMBERS.xlsx`.
#' @param reparto_selection Character vector of resident last_names
#'   (UPPERCASE) chosen for the REPARTO block of the target month.
#' @return Named list (residents, specialists, reparto_block,
#'   clinic_only_attendings, inpatient_attendings,
#'   juniors_eligible_for_substitution, meta).
#' @export
derive_roster <- function(parsed_inputs, members_path,
                          reparto_selection = character()) {
  members <- read_iov_members(members_path)

  # Distinct residents in this month's desiderata
  desiderata_residents <- dplyr::distinct(
    parsed_inputs$desiderata_long, .data$resident, .data$year
  )

  matched <- .iov_match_residents(desiderata_residents, members)

  reparto_norm <- .iov_normalize_name(reparto_selection)

  residents <- tibble::tibble(
    last_name        = matched$last_name_resolved,
    first_name       = matched$first_name_resolved,
    desiderata_name  = matched$desiderata_name,
    year             = matched$year,
    matched          = matched$matched,
    ambiguous        = matched$ambiguous
  )
  residents$in_reparto_block <- !is.na(residents$last_name) &
    residents$last_name %in% reparto_norm

  juniors_pool <- residents$last_name[
    !is.na(residents$last_name) &
      residents$year %in% c("1", "2") &
      !residents$in_reparto_block
  ]

  specialists_members <- dplyr::filter(
    members, .data$role %in% c("Direttrice", "Specialista")
  )
  specialists <- tibble::tibble(
    last_name           = specialists_members$last_name,
    first_name          = specialists_members$first_name,
    role                = specialists_members$role,
    primary_group       = specialists_members$primary_group,
    subgroup_secondary  = specialists_members$subgroup_secondary,
    in_guardie_rotation = specialists_members$in_guardie_rotation,
    fasi_i_eligible     = specialists_members$reperibile_fasi_i
  )
  specialists$is_clinic_only    <- specialists$last_name %in% .iov_clinic_only_attendings
  specialists$is_full_inpatient <- specialists$last_name %in% .iov_inpatient_attendings

  list(
    residents                          = residents,
    specialists                        = specialists,
    reparto_block                      = reparto_norm,
    clinic_only_attendings             = .iov_clinic_only_attendings,
    inpatient_attendings               = .iov_inpatient_attendings,
    juniors_eligible_for_substitution  = juniors_pool,
    meta = list(
      target_month   = parsed_inputs$target_month,
      members_path   = members_path,
      members_count  = nrow(members),
      ambiguous_names = matched$desiderata_name[matched$ambiguous]
    )
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-roster.R")'
```

Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add R/iov_roster.R tests/testthat/test-iov-roster.R
git commit -m "feat(iov): derive_roster orchestrator builds resolved_roster"
```

---

## Task 2.7: Scaffold `R/iov_validate.R`

Empty module with header listing the public function.

**Files:**
- Create: `R/iov_validate.R`

- [ ] **Step 1: Write the skeleton**

```r
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
```

- [ ] **Step 2: Verify pkgload picks up the file**

Run:
```bash
Rscript -e 'pkgload::load_all("."); cat("loaded\n")'
```

Expected: `loaded`.

- [ ] **Step 3: Commit**

```bash
git add R/iov_validate.R
git commit -m "feat(iov): scaffold R/iov_validate.R module"
```

---

## Task 2.8: HARD blocker check functions

Five private helpers, each returning `character()` of blocker messages (empty if no issues). Then the public `validate_iov_inputs()` will aggregate them.

The five blockers:
1. **Unknown residents in assenze**: an `assenze_long$person` whose normalised name isn't in `resolved_roster$residents$last_name` AND isn't in `resolved_roster$specialists$last_name`. (Assenze covers both attendings and residents; the row just shouldn't reference a stranger.)
2. **Ambiguous Sartori without disambiguation**: any `resolved_roster$residents$ambiguous == TRUE`.
3. **Unknown year tags**: any resident with `year == "unknown"` AND `year` shouldn't have failed parsing (parser would have flagged "0" for ex-residents; "unknown" means a fill color we didn't recognise).
4. **REPARTO selection includes non-resident**: any name in `resolved_roster$reparto_block` that doesn't appear in `resolved_roster$residents$last_name`.
5. **Month inconsistency**: `parsed_inputs$prospetto` contains zero rows in `parsed_inputs$target_month`. (PROSPETTO may cover Jul-Sep, but at minimum the target month must appear.)

Each helper returns Italian-language messages with the offending names, ready for display in the Shiny panel.

**Files:**
- Modify: `R/iov_validate.R` (append 5 private helpers)
- Create: `tests/testthat/test-iov-validate.R`

- [ ] **Step 1: Write failing tests for the 5 blockers**

```r
fixture_roster <- function() {
  # Build a minimal resolved_roster structure for tests.
  list(
    residents = tibble::tibble(
      last_name = c("BOSIO", "MASSA", NA),  # one row failed matching
      first_name = c("Marco", "Elena", NA),
      desiderata_name = c("Bosio", "Massa", "Sartori"),
      year = c("5", "1", "unknown"),
      matched = c(TRUE, TRUE, FALSE),
      ambiguous = c(FALSE, FALSE, TRUE),
      in_reparto_block = c(FALSE, FALSE, FALSE)
    ),
    specialists = tibble::tibble(
      last_name = c("LONARDI", "PROCACCIO"),
      first_name = c("Sara", "Giorgio"),
      role = c("Direttrice", "Specialista"),
      primary_group = c("Direzione", "GASTROENTERICO"),
      subgroup_secondary = c(NA_character_, "Pancreas"),
      in_guardie_rotation = c(FALSE, TRUE),
      fasi_i_eligible = c(FALSE, FALSE),
      is_clinic_only = c(TRUE, FALSE),
      is_full_inpatient = c(FALSE, FALSE)
    ),
    reparto_block                     = c("MASSA"),
    clinic_only_attendings            = c("LONARDI", "BERGAMO"),
    inpatient_attendings              = c("GALIANO", "BOLSHINSKY"),
    juniors_eligible_for_substitution = c("MASSA"),
    meta = list(target_month = "2026-07", members_count = 11L,
                ambiguous_names = "Sartori")
  )
}

fixture_inputs <- function() {
  list(
    target_month = "2026-07",
    prospetto = tibble::tibble(
      date = as.Date(c("2026-07-04", "2026-07-05")),
      dow = c("Sab", "Dom"),
      day_unit = c("ANESTESTISTA", "ANESTESTISTA"),
      night_unit = c("ONCOLOGIA 1", "ONCOLOGIA 2")
    ),
    desiderata_long = tibble::tibble(
      resident = c("Bosio", "Massa"), year = c("5", "1"),
      date = as.Date(rep("2026-07-04", 2)), dow = "Sab",
      shift = "GIORNO", status = "available",
      preference = "neutral", raw_value = NA_character_
    ),
    assenze_long = tibble::tibble(
      date = as.Date("2026-07-02"), dow = "Gio",
      person = "Procaccio", absence_type = "ferie", slot = "full_day"
    )
  )
}

test_that(".iov_check_unknown_residents flags assenze rows referencing strangers", {
  r <- fixture_roster()
  i <- fixture_inputs()

  # Happy path: Procaccio is a known specialist → no blockers
  expect_equal(.iov_check_unknown_residents(i, r), character(0))

  # Inject a stranger
  i$assenze_long <- dplyr::bind_rows(i$assenze_long, tibble::tibble(
    date = as.Date("2026-07-03"), dow = "Ven",
    person = "Stranieri", absence_type = "ferie", slot = "full_day"
  ))
  blockers <- .iov_check_unknown_residents(i, r)
  expect_length(blockers, 1L)
  expect_match(blockers, "Stranieri")
})

test_that(".iov_check_ambiguous_sartori flags unresolved ambiguity", {
  r <- fixture_roster()
  blockers <- .iov_check_ambiguous_sartori(r)
  expect_length(blockers, 1L)
  expect_match(blockers, "Sartori")
})

test_that(".iov_check_unknown_years flags residents with year='unknown'", {
  r <- fixture_roster()  # Sartori has year='unknown'
  blockers <- .iov_check_unknown_years(r)
  expect_length(blockers, 1L)
  expect_match(blockers, "Sartori")
})

test_that(".iov_check_reparto_validity flags names not in resident pool", {
  r <- fixture_roster()
  # MASSA is in the pool → no blocker
  expect_equal(.iov_check_reparto_validity(r), character(0))
  # Inject a non-resident name into REPARTO
  r$reparto_block <- c(r$reparto_block, "GHOST")
  blockers <- .iov_check_reparto_validity(r)
  expect_length(blockers, 1L)
  expect_match(blockers, "GHOST")
})

test_that(".iov_check_month_consistency flags PROSPETTO without target month rows", {
  i <- fixture_inputs()
  expect_equal(.iov_check_month_consistency(i), character(0))

  # Set target month to one with no PROSPETTO rows
  i$target_month <- "2026-12"
  blockers <- .iov_check_month_consistency(i)
  expect_length(blockers, 1L)
  expect_match(blockers, "2026-12")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-validate.R")'
```

Expected: FAIL — none of the 5 functions defined yet.

- [ ] **Step 3: Write the 5 helpers**

Append to `R/iov_validate.R`:

```r
.iov_check_unknown_residents <- function(parsed_inputs, resolved_roster) {
  if (nrow(parsed_inputs$assenze_long) == 0L) return(character(0))
  known <- c(resolved_roster$residents$last_name,
             resolved_roster$specialists$last_name)
  known <- known[!is.na(known)]
  persons <- .iov_normalize_name(parsed_inputs$assenze_long$person)
  unknown <- setdiff(unique(persons), known)
  if (length(unknown) == 0L) return(character(0))
  sprintf("Persona '%s' nel file assenze non trovata nel roster IOV_MEMBERS",
          unknown)
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-validate.R")'
```

Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add R/iov_validate.R tests/testthat/test-iov-validate.R
git commit -m "feat(iov): HARD blocker checks for resident/REPARTO/month consistency"
```

---

## Task 2.9: SOFT warning check functions

Four private helpers, each returning `character()` of warning messages. These are SURFACED to the user but DON'T block the solver.

The four warnings:
1. **Weekend off-cap**: residents whose desiderata mark > 2 weekends as `status %in% c("ferie", "congresso", "unavailable_soft")`. Spec §5.2 S4: soft cap is 2/4 (or 3/5).
2. **Unknown year**: residents whose `year == "unknown"` — same names as the blocker but here as a soft notice if the user has manually overridden the blocker check.
3. **PROSPETTO/desiderata coherence**: ONCO 1 night dates in `parsed_inputs$prospetto` should have at least N residents in `parsed_inputs$desiderata_long` with `shift == "NOTTE"` on the same date and `status %in% c("available", "unavailable_soft", "favorite")`. If too few are available, the solver may struggle; warn early.
4. **Clinic-only attending in assenze**: Lonardi or Bergamo appears in `assenze_long`. They never do guardie so absence rows for them are noise; warn to flag a possible misuse of the input file.

**Files:**
- Modify: `R/iov_validate.R` (append 4 helpers)
- Modify: `tests/testthat/test-iov-validate.R` (append tests)

- [ ] **Step 1: Write failing tests for the 4 warnings**

Append to `tests/testthat/test-iov-validate.R`:

```r
test_that(".iov_check_weekend_off_cap flags residents over the 2-of-4 limit", {
  r <- fixture_roster()
  # Bosio marks 3 weekends as ferie → violation
  i <- fixture_inputs()
  i$desiderata_long <- tibble::tibble(
    resident = rep("Bosio", 3),
    year = rep("5", 3),
    date = as.Date(c("2026-07-04", "2026-07-11", "2026-07-18")),
    dow = rep("Sab", 3),
    shift = rep("GIORNO", 3),
    status = rep("ferie", 3),
    preference = rep("neutral", 3),
    raw_value = rep("AF", 3)
  )
  warnings <- .iov_check_weekend_off_cap(i, r, threshold = 2L)
  expect_length(warnings, 1L)
  expect_match(warnings, "Bosio")
})

test_that(".iov_check_weekend_off_cap returns empty when all under threshold", {
  r <- fixture_roster()
  i <- fixture_inputs()
  # Only 1 weekend off for Bosio
  i$desiderata_long <- tibble::tibble(
    resident = "Bosio", year = "5",
    date = as.Date("2026-07-04"), dow = "Sab", shift = "GIORNO",
    status = "ferie", preference = "neutral", raw_value = "AF"
  )
  warnings <- .iov_check_weekend_off_cap(i, r, threshold = 2L)
  expect_equal(warnings, character(0))
})

test_that(".iov_check_unknown_year_warning flags unknown years as soft signal", {
  r <- fixture_roster()
  warnings <- .iov_check_unknown_year_warning(r)
  expect_length(warnings, 1L)
})

test_that(".iov_check_prospetto_desiderata_coherence flags ONCO 1 night with no available residents", {
  r <- fixture_roster()
  i <- fixture_inputs()
  # PROSPETTO has Sat Jul 4 as ONCO 1 night, but desiderata has no NOTTE rows.
  warnings <- .iov_check_prospetto_desiderata_coherence(i)
  expect_true(any(grepl("2026-07-04", warnings)))
})

test_that(".iov_check_clinic_only_in_assenze flags Lonardi/Bergamo in assenze", {
  r <- fixture_roster()
  i <- fixture_inputs()
  i$assenze_long <- dplyr::bind_rows(i$assenze_long, tibble::tibble(
    date = as.Date("2026-07-10"), dow = "Ven",
    person = "Lonardi", absence_type = "ferie", slot = "full_day"
  ))
  warnings <- .iov_check_clinic_only_in_assenze(i, r)
  expect_length(warnings, 1L)
  expect_match(warnings, "Lonardi")
})
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-validate.R")'
```

Expected: FAIL — none of the 4 functions defined yet.

- [ ] **Step 3: Write the 4 helpers**

Append to `R/iov_validate.R`:

```r
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-validate.R")'
```

Expected: 10 tests pass total in this file (5 from Task 2.8 + 5 here).

- [ ] **Step 5: Commit**

```bash
git add R/iov_validate.R tests/testthat/test-iov-validate.R
git commit -m "feat(iov): SOFT warning checks for weekend cap, coherence, clinic-only"
```

---

## Task 2.10: `validate_iov_inputs()` public orchestrator

Aggregates the 9 private check functions into a single public call. Returns `list(blockers, warnings)` where each is a character vector (potentially empty).

The function is dumb on purpose: no branching, no early-exit. All checks always run so the user sees the FULL picture in one pass and doesn't have to iterate fix→re-validate→fix→re-validate.

**Files:**
- Modify: `R/iov_validate.R` (append public function)
- Modify: `tests/testthat/test-iov-validate.R` (append test)

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-iov-validate.R`:

```r
test_that("validate_iov_inputs aggregates all blockers and warnings", {
  r <- fixture_roster()  # has 1 ambiguous Sartori + 1 unknown year
  i <- fixture_inputs()

  result <- validate_iov_inputs(i, r)

  expect_named(result, c("blockers", "warnings"))
  expect_type(result$blockers, "character")
  expect_type(result$warnings, "character")

  # Blockers: ambiguous Sartori + unknown year (Sartori again)
  expect_true(length(result$blockers) >= 2L)
  expect_true(any(grepl("Sartori", result$blockers)))

  # Warnings: unknown_year_warning fires for the same Sartori (soft mirror)
  # + prospetto_desiderata_coherence likely fires (no NOTTE rows in fixture)
  expect_true(length(result$warnings) >= 1L)
})

test_that("validate_iov_inputs returns empty vectors on fully-clean inputs", {
  # Build a clean fixture: no ambiguous, no unknown year, all dates aligned
  r <- list(
    residents = tibble::tibble(
      last_name = "BOSIO", first_name = "Marco",
      desiderata_name = "Bosio", year = "5",
      matched = TRUE, ambiguous = FALSE, in_reparto_block = FALSE
    ),
    specialists = tibble::tibble(
      last_name = c("LONARDI", "PROCACCIO"),
      first_name = c("Sara", "Giorgio"),
      role = c("Direttrice", "Specialista"),
      primary_group = c("Direzione", "GASTROENTERICO"),
      subgroup_secondary = c(NA_character_, "Pancreas"),
      in_guardie_rotation = c(FALSE, TRUE),
      fasi_i_eligible = c(FALSE, FALSE),
      is_clinic_only = c(TRUE, FALSE), is_full_inpatient = c(FALSE, FALSE)
    ),
    reparto_block = character(),
    clinic_only_attendings = c("LONARDI", "BERGAMO"),
    inpatient_attendings = c("GALIANO", "BOLSHINSKY"),
    juniors_eligible_for_substitution = character(),
    meta = list(target_month = "2026-07", members_count = 2L,
                ambiguous_names = character())
  )
  i <- list(
    target_month = "2026-07",
    prospetto = tibble::tibble(
      date = as.Date("2026-07-04"), dow = "Sab",
      day_unit = "ANESTESTISTA", night_unit = "ONCOLOGIA 2"  # not ONCO 1!
    ),
    desiderata_long = tibble::tibble(
      resident = "Bosio", year = "5", date = as.Date("2026-07-04"),
      dow = "Sab", shift = "GIORNO", status = "available",
      preference = "neutral", raw_value = NA_character_
    ),
    assenze_long = tibble::tibble(
      date = as.Date(character()), dow = character(), person = character(),
      absence_type = character(), slot = character()
    )
  )
  result <- validate_iov_inputs(i, r)
  expect_equal(result$blockers, character(0))
  expect_equal(result$warnings, character(0))
})
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-validate.R")'
```

Expected: FAIL with `could not find function "validate_iov_inputs"`.

- [ ] **Step 3: Write the orchestrator**

Append to `R/iov_validate.R`:

```r
#' Run all input validation checks and return a structured result.
#'
#' Blockers are HARD errors that prevent the solver. Warnings are SOFT
#' issues to surface in the Shiny panel but allow generation.
#'
#' @param parsed_inputs Named list from `read_iov_inputs()`.
#' @param resolved_roster Named list from `derive_roster()`.
#' @return Named list (blockers, warnings). Each is a character vector
#'   (possibly empty) of Italian-language messages.
#' @export
validate_iov_inputs <- function(parsed_inputs, resolved_roster) {
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
    .iov_check_clinic_only_in_assenze(parsed_inputs, resolved_roster)
  )
  list(blockers = blockers, warnings = warnings)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-validate.R")'
```

Expected: 12 tests pass total in this file.

- [ ] **Step 5: Commit**

```bash
git add R/iov_validate.R tests/testthat/test-iov-validate.R
git commit -m "feat(iov): validate_iov_inputs orchestrator aggregates all checks"
```

---

## Task 2.11: Golden integration tests against real `iov/` files

End-to-end validation: load the real PROSPETTO + desiderata + assenze for July 2026, run `read_iov_inputs()` → `derive_roster()` with the July REPARTO selection → `validate_iov_inputs()`, then assert against the golden expectations from project memory.

**Files:**
- Create: `tests/testthat/test-iov-roster-golden.R`
- Create: `tests/testthat/test-iov-validate-golden.R`

- [ ] **Step 1: Write the roster golden test**

Create `tests/testthat/test-iov-roster-golden.R`:

```r
.iov_paths_for_july <- function() {
  list(
    prospetto    = "iov/PROSPETTO GUARDIE 2026_LUGLIO_SETTEMBRE_DEF_.xlsx",
    desiderata   = "iov/Turni coguardia + guardia 2026 specializzandi.xlsx",
    assenze      = "iov/analysis/assenze 07.2026.xlsx",
    members      = "iov/analysis/IOV_MEMBERS.xlsx"
  )
}

test_that("derive_roster on real July 2026 inputs matches the memory baseline", {
  p <- .iov_paths_for_july()
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

  # July active roster size — 21 distinct residents in desiderata-long is the
  # production count (memory baseline).
  active <- roster$residents$last_name[!is.na(roster$residents$last_name)]
  expect_gte(length(unique(active)), 21L)

  # All 4 REPARTO names must resolve to matched residents
  expect_setequal(roster$reparto_block, reparto_july)
  expect_true(all(reparto_july %in% active))

  # Juniors eligible for substitution: year 1 or 2, NOT in REPARTO
  # Memory baseline: MASSA (1°) + BERTIN, BIONDI, BONELLO, DAL CENGIO, SARUBBI (2°) = 6
  juniors <- roster$juniors_eligible_for_substitution
  expect_true("MASSA" %in% juniors)
  expect_true("BERTIN" %in% juniors)
  expect_false("BIVONA" %in% juniors)  # in REPARTO

  # Specialists: Lonardi & Bergamo flagged clinic-only; Galiano & Bolshinsky
  # flagged full-inpatient
  expect_true(roster$specialists$is_clinic_only[
    roster$specialists$last_name == "LONARDI"])
  expect_true(roster$specialists$is_full_inpatient[
    roster$specialists$last_name == "GALIANO"])
  expect_true(roster$specialists$fasi_i_eligible[
    roster$specialists$last_name == "BOLSHINSKY"])

  # Members count from the canonical file (~61 per memory)
  expect_gte(roster$meta$members_count, 60L)
})
```

- [ ] **Step 2: Write the validation golden test**

Create `tests/testthat/test-iov-validate-golden.R`:

```r
.iov_paths_for_july_v <- function() {
  list(
    prospetto    = "iov/PROSPETTO GUARDIE 2026_LUGLIO_SETTEMBRE_DEF_.xlsx",
    desiderata   = "iov/Turni coguardia + guardia 2026 specializzandi.xlsx",
    assenze      = "iov/analysis/assenze 07.2026.xlsx",
    members      = "iov/analysis/IOV_MEMBERS.xlsx"
  )
}

test_that("validate_iov_inputs on real July 2026 inputs has no blockers and reasonable warnings", {
  p <- .iov_paths_for_july_v()
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

  # On clean production data we EXPECT no blockers. If this fails, investigate
  # whether the roster module has a real issue OR whether the source files
  # changed (e.g. caposala added a new resident not yet in IOV_MEMBERS).
  expect_equal(result$blockers, character(0),
               info = paste("Unexpected blockers:",
                            paste(result$blockers, collapse = " | ")))

  # Warnings are EXPECTED to fire for a real workbook. Just sanity-check the
  # vector is character (might be empty if input is unusually clean).
  expect_type(result$warnings, "character")
})
```

- [ ] **Step 3: Run the golden tests**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-roster-golden.R")'
Rscript -e 'pkgload::load_all("."); testthat::test_file("tests/testthat/test-iov-validate-golden.R")'
```

Expected (locally): all tests pass. If `blockers` is non-empty, do NOT commit — investigate by reading the blocker messages (they're descriptive). On CI without the iov/ files: tests skipped.

- [ ] **Step 4: Commit**

```bash
git add tests/testthat/test-iov-roster-golden.R tests/testthat/test-iov-validate-golden.R
git commit -m "test(iov): golden integration tests for roster + validation on July 2026"
```

---

## Task 2.12: Full-suite run + `R CMD check` + final fixups

Verifies the IOV additions didn't break v1 or P-IOV-1, and that `R CMD check` is still clean.

- [ ] **Step 1: Run the entire test suite**

Run:
```bash
Rscript -e 'pkgload::load_all("."); testthat::test_local()'
```

Expected: all 257 prior tests pass plus the new IOV roster + validate tests. Approximate total: 257 + ~24 = ~281 PASS / 1 SKIP / 0 FAIL.

- [ ] **Step 2: Run `R CMD check`**

Run:
```bash
Rscript -e 'devtools::check(args = "--no-manual", quiet = FALSE)' 2>&1 | tail -30
```

Expected: `0 errors ✓ | 1 warning ✗ | 5 notes ✗` (same baseline as after P-IOV-1's chore commit — the warning is pre-existing v1 non-ASCII; notes are pre-existing). If new warnings appear:
- `no visible binding for global variable .data` in iov_roster/validate → the package already imports `.data` via `R/shifthappens-package.R`; nothing to add. If R CMD check complains about a NEW global like `desiderata_name`, add `utils::globalVariables(c("desiderata_name", ...))` near the imports.
- `undocumented arguments` for new private helpers → add `@noRd` + `@param` for each (same pattern as `R/iov_parse.R` private helpers).

- [ ] **Step 3: Commit any required fixups**

If `R CMD check` required changes (typically `@noRd` annotations on the new private helpers, or `utils::globalVariables`), commit them:

```bash
git add R/iov_roster.R R/iov_validate.R
git commit -m "chore(iov): satisfy R CMD check for roster + validate modules"
```

If no fixups were required, skip this step.

---

## Self-Review

**Spec coverage (against `2026-05-21-iov-planner-design.md`):**
- §3.1 module map mentions `R/iov_roster.R` + `R/iov_validate.R` → ✓ both created in Tasks 2.2 / 2.7.
- §4.2 `resolved_roster` shape (residents/specialists/reparto_block/clinic_only_attendings/inpatient_attendings) → ✓ returned by `derive_roster` in Task 2.6, with additional `juniors_eligible_for_substitution` and `meta` fields (additive, not contradictory).
- §5.1 H4 (REPARTO block) → ✓ `derive_roster` accepts `reparto_selection` and flags `in_reparto_block` per resident; validation checks selection validity (Task 2.8).
- §5.1 H7 (clinic-only ineligibility) → ✓ `specialists$is_clinic_only` set by constant; `validate_iov_inputs` warns if clinic-only appears in assenze (Task 2.9).
- §5.2 S4 (weekend off cap) → ✓ `.iov_check_weekend_off_cap` (Task 2.9), threshold parametrised.
- §11 open questions: parser exists for Sartori disambiguation (Task 2.5), apostrophe drift (Task 2.4) — addressed.

**Placeholder scan:** No "TODO", no "TBD", no "similar to Task N", no "add appropriate error handling". Each step ships code.

**Type consistency:**
- `derive_roster()` returns a list with stable keys used by `validate_iov_inputs()` (residents$last_name, residents$ambiguous, residents$year, etc.). Same names across tasks. ✓
- `validate_iov_inputs()` returns `list(blockers, warnings)` — both character vectors. Tested explicitly. ✓
- `.iov_normalize_name()` always returns character of same length as input (NA in, NA out). Used consistently. ✓
- `parsed_inputs` shape (`target_month`, `prospetto`, `desiderata_long`, `assenze_long`) matches `read_iov_inputs()` output from P-IOV-1. ✓

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-25-iov-planner-p-iov-2.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for this plan because each task has a clean TDD gate and tasks 2.3-2.6 build on each other in tight sequence.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints. Good if you want to watch each step live.

Which approach?
