# IOV Planner — Design Specification

**Status:** Draft for review
**Date:** 2026-05-21
**Author:** Federico Nichetti (with brainstorming via Claude Code)
**Source artefacts:**
- `iov/analysis/IOV_RULES.md` — IOV constraint catalogue
- `iov/analysis/IOV_MEMBERS.xlsx` — canonical roster of attendings + residents
- `iov/analysis/IOV_SHIFTS_2026.xlsx` — historical Feb-Jun 2026 assignments
- `iov/analysis/desiderata_07_2026.xlsx` — derived long-format desiderata for July 2026
- `iov/analysis/extract_desiderata_07_2026.R` — extraction script (re-runnable)
- `iov/PROSPETTO GUARDIE 2026_LUGLIO_SETTEMBRE_DEF_.xlsx` — inter-unit weekend attending night rota
- `iov/Turni coguardia + guardia 2026 specializzandi.xlsx` — multi-year resident desiderata workbook
- Original ShiftHappens spec — `docs/superpowers/specs/2026-04-25-shifthappens-design.md`

---

## 1. Goal & Scope

### 1.1 Goal

Extend the ShiftHappens app with a dedicated **"IOV Planner" tab** that generates the four monthly schedule documents for IOV (Istituto Oncologico Veneto) UOC Oncologia 1 — guardie, turni specialisti, turni specializzandi, prospetto ambulatori — from the three input workbooks already in use at IOV. The planner must respect the IOV-specific shift taxonomy and the attending-substitution rule for weekend nights, and must be operable by the caposala without touching code.

### 1.2 In scope (IOV Planner v1, target month: July 2026)

- New top-level tab `IOV Planner` in `app.R` alongside the existing generic flow. Generic flow is not modified.
- Dedicated `R/iov_*.R` modules. The existing `R/model_build.R` / `R/model_solve.R` are NOT generalized to fit IOV — the IOV shift taxonomy is too domain-specific.
- Reused utilities from ShiftHappens v1: `R/holidays_it.R`, `R/i18n_it.R`, `R/ui_helpers.R`, `R/io_write.R`.
- Three file uploaders (PROSPETTO, desiderata specializzandi, assenze specialisti), internal parsers, derived roster, in-app validation panel, MILP solver, output bundle download (`.zip` with 4 xlsx).
- Output: 3 long-format xlsx + 1 grid-format xlsx (ambulatori prospetto).
- Black-box ONCO 2: the planner never models ONCO 2 internals; cells covered by the other unit are written as the sentinel string `ONCO 2`.
- Manual REPARTO selection: the caposala picks the 4 ward-block residents for the month via the UI before solving.
- Backtest harness against Feb-Jun 2026 historical data; ≥70% match is the acceptance gate (diagnostic, not a hard pass/fail per individual cell).

### 1.3 Out of scope (deferred to v1.1+)

- Multi-unit support (the planner solves ONCO 1 only; ONCO 2 stays a black box).
- Automated REPARTO rotation deduction from history (always manual input in v1).
- Editing of generated schedules in-app (download → edit in Excel → re-import if needed).
- Cross-month rolling balance (each month is solved independently; equity is per-month only).
- Holidays in months other than July 2026 (the holiday handler reuses `R/holidays_it.R` but no IOV-specific local holidays are added in v1).
- Migration of `R/model_build.R` to a unified abstract model.
- Pixel-perfect replication of the historical PDF/xlsx layouts (clean long-format chosen instead).
- Mobile or tablet layout for the IOV Planner tab.

---

## 2. Locked Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Architecture | **Dedicated `R/iov_*.R` modules, new tab in existing app.** Not a separate app, not a generalization of v1. | IOV has 8 shift types per day, ambulatori grid, residency-year constraints, attending-substitution — generalizing v1 would balloon the spec and risk regressions. Keeping it separate isolates risk. |
| 2 | Output layout | **Clean long-format xlsx for guardie + turni specialisti + turni specializzandi. Grid format for ambulatori.** | Long-format = diffable, re-importable, machine-readable. Ambulatori is naturally a grid (date × room) and far more legible that way for human review. |
| 3 | ONCO 2 visibility | **Black box.** When PROSPETTO assigns `ONCO 2` to a weekend night, the planner writes the literal sentinel `ONCO 2`. | Matches the existing Feb-Jun 2026 historical pattern. ONCO 2 has its own pool the caposala cannot see; respecting that boundary keeps the planner decoupled. |
| 4 | Input UX | **Three file uploaders** (PROSPETTO, desiderata specializzandi, assenze specialisti). Internal parser. No template re-formatting required. | Caposala already produces these files for the manual workflow; zero retraining cost. |
| 5 | REPARTO selection | **Manual input** via UI form (4 dropdowns populated from the parsed resident roster). | Clinical decision, not algorithmic. Trying to deduce from history is fragile and over-engineered for v1. |
| 6 | Acceptance gate | **≥70% match against backtest of Feb-Jun 2026.** Below 70% triggers investigation of unmodelled constraints. Match score is diagnostic, not per-cell pass/fail. | Caposala makes subjective tradeoffs the model can't see; demanding perfect replay would invent false constraints. 70% is the threshold that distinguishes "respects the rules" from "approximates the caposala". |
| 7 | Solver | **Same stack as v1**: `ompr` + `ROI` + `ROI.plugin.glpk` + `Rglpk`. | Already vetted on Connect Cloud, already in the project's renv lockfile. No reason to introduce a second solver dependency. |
| 8 | Weekend-row convention | **Row 1 = GIORNO (08-20), row 2 = NOTTE (20-08)** in the desiderata source workbook. Weekday rows = NOTTE only. | User-confirmed 2026-05-21. Already encoded in `extract_desiderata_07_2026.R`. |
| 9 | Attending night-guard substitution | **Replaces exactly ONE junior** (1° or 2° year) on either Prima Guardia NOTTE or Coguardia NOTTE for each ONCO 1 weekend night listed in the PROSPETTO. The other resident of the couple remains. | User-confirmed 2026-05-21. Same rule applies symmetrically to ONCO 2 weekend nights (handled by sentinel). |
| 10 | Weekend availability cap | **Soft preference**: max 2/4 (or 3/5) weekend rows unavailable per resident per month. Violations emit warnings; do not block the solve. | User-confirmed 2026-05-21. Hard enforcement would risk infeasibility from data-entry quirks. |
| 11 | Yellow-cell preference | **Soft bonus** in objective. | User-confirmed 2026-05-21. 44 yellow cells observed in July 2026 source — under-used by residents but worth honoring when feasible. |

---

## 3. Architecture

### 3.1 Module map

```
R/
├── iov_parse.R           # parse_prospetto(), parse_desiderata_specializzandi(),
│                         # parse_assenze_specialisti() — port of extract_*.R
├── iov_roster.R          # derive_roster(), cross_ref_members(),
│                         # validate_roster_against_members()
├── iov_validate.R        # check_weekend_off_cap(), check_unknown_residents(),
│                         # check_year_coverage(), check_reparto_selection()
├── iov_model.R           # build_iov_model() — ompr abstract_model with the
│                         # IOV-specific decision variables + constraints
├── iov_solve.R           # solve_iov_model() — wraps ROI.plugin.glpk, returns
│                         # solution tibble + status
├── iov_postprocess.R     # solution_to_long_guardie(), …_specialisti(),
│                         # …_specializzandi(), solution_to_grid_ambulatori()
├── iov_output.R          # write_iov_bundle() — packages 4 xlsx into one zip
├── iov_backtest.R        # backtest_against_historical() — compares solver
│                         # output to IOV_SHIFTS_2026.xlsx for any past month
└── shiny/iov_module.R    # mod_iov_planner_ui() / mod_iov_planner_server()
                          # — the Shiny module wiring the tab
```

### 3.2 Tab placement in `app.R`

A top-level `bslib::nav_panel("IOV Planner", icon = bsicons::bs_icon("hospital"), …)` added to the existing `navset_pill`. Generic flow stays the default tab.

### 3.3 Solver stack

Identical to v1 — `ompr` builds the abstract model, `ROI.plugin.glpk` is the default solver, `Rglpk` is the underlying engine. No new package dependencies are introduced. Solver time budget: 60 seconds per solve (matches v1 default).

---

## 4. Data Model

### 4.1 Inputs (3 user-uploaded xlsx)

| Input | Source file | Sheet | What we extract |
|---|---|---|---|
| Inter-unit attending night rota | `PROSPETTO GUARDIE 2026_*_DEF_.xlsx` | first sheet (varies by quarter) | For each weekend day in target month: which unit (ONCOLOGIA 1, ONCOLOGIA 2, SENOLOGICA 1, CHIRURGIA T. MOLLI) covers the night. |
| Resident desiderata | `Turni coguardia + guardia 2026 specializzandi.xlsx` | sheet matching target month (e.g. "Luglio 2026") | Per (resident × day × shift): status (`available` / `unavailable_soft` / `ferie` / `congresso`), preference (yellow → favorite). Plus year tag from row-3 fill color. |
| Attending absences | `assenze MM.YYYY.xlsx` | `Foglio1` | Per attending: dates of AF/AC/AF pomeriggio/no guardia/no rep. |

### 4.2 Parsed in-app state

```
parsed_inputs <- list(
  target_month    = "2026-07",
  prospetto       = tibble(date, dow, day_unit, night_unit),
  desiderata_long = tibble(date, dow, shift, resident, year, status,
                           preference, raw_value),
  assenze_long    = tibble(date, dow, person, absence_type, slot),
  weekend_attending_nights = tibble(date, role = "ONCO 1 attending night",
                                    junior_to_displace = NA)  # filled by solver
)

resolved_roster <- list(
  residents = tibble(person, year, in_rotation, source),
  specialists = tibble(person, in_guardie, in_clinic_only, disease_group),
  reparto_block = c("Bof", "Bivona", "Bravi", "Bloise"),   # USER INPUT
  clinic_only_attendings = c("Lonardi", "Bergamo"),         # constant
  inpatient_attendings   = c("Galiano", "Bolshinsky")       # constant
)
```

### 4.3 Year-color map (locked, version-controlled in `R/iov_parse.R`)

| Fill RGB | Year |
|---|---|
| `FFFF0000`, `FF980000`, `FFE06666` | 0 (ex-resident, not in rotation) |
| `FFF4CCCC`, `FFEAD1DC` | 5° anno (rosa) |
| `FF9FC5E8`, `FFCFE2F3`, `FFC9DAF8`, `FFA4C2F4` | 4° anno (azzurro) |
| `FFF6B26B`, `FFF9CB9C`, `FFFCE5CD` | 3° anno (arancio) |
| `FFD9EAD3`, `FF93C47D`, `FFB6D7A8` | 2° anno (verde) |
| `FFB4A7D6`, `FFD9D2E9` | 1° anno (viola) |
| `FFFFFF00`, `FFFFF2CC`, `FFFFE599`, `FFFFD966` | (any year) — yellow preference fill in data cells |

Unknown fills → `year = "unknown"` + validation warning.

---

## 5. Constraints

### 5.1 Hard constraints

| # | Constraint | Affects |
|---|---|---|
| H1 | If resident has `AF` or `AC` on day N, they cannot be assigned any guardia / DH / clinic on day N. | Residents |
| H2 | Buffer: H1 extends to the NOTTE shift of day N-1 (20-08 ending at 08:00 day N) and NOTTE of day N (starting 20:00 day N). | Residents |
| H3 | Post-night recovery: a resident on Prima Guardia NOTTE or Coguardia NOTTE day N cannot be assigned the morning clinic / DH on day N+1. | Residents |
| H4 | REPARTO block: the 4 user-selected REPARTO residents are unavailable for clinic, guardie, reperibile for the entire target month. | Residents |
| H5 | Weekend coverage: each Sat/Sun needs Prima Guardia GIORNO + Coguardia GIORNO + Prima Guardia NOTTE + Coguardia NOTTE = 4 distinct residents from the ONCO 1 active pool. | Residents |
| H6 | Attending-night substitution: on each ONCO 1 weekend night listed in PROSPETTO, exactly one of {Prima Guardia NOTTE, Coguardia NOTTE} is an ONCO 1 attending (from the eligible pool) and the other is a resident. The displaced slot's resident must be a junior (1° or 2° anno). | Residents + Attendings |
| H7 | Specialists ineligibility: Lonardi, Bergamo, Galiano, Bolshinsky never assigned guardie or reperibile. Lonardi, Bergamo also never assigned regular ambulatori (clinic-only attendings keep their existing personal schedules, not handled by this planner). | Attendings |
| H8 | DH pomeriggio pair: each `pomeriggio_feriale` slot mon-fri = 1 attending + 1 resident. The attending's disease group should match the room's afternoon theme (theme defined by day-of-week in `R/iov_model.R` rules table). | Attendings + Residents |
| H9 | Sentinel preservation: when PROSPETTO assigns a non-ONCO 1 unit (ONCOLOGIA 2 / SENOLOGICA 1 / CHIRURGIA T. MOLLI) to a weekend night, the corresponding Prima Guardia NOTTE cell in the output is the literal string of that unit; resident assignment is suppressed for that cell. | Output |
| H10 | At most one shift per person per day. | All |

### 5.2 Soft constraints (weighted sum in MILP objective)

| # | Soft preference | Weight default | Direction |
|---|---|---|---|
| S1 | Equity: minimize variance of total guardie count across residents (computed within pool after REPARTO removal). | 1.0 | Minimize |
| S2 | Yellow-cell preference: bonus for assigning a resident to a date/shift they marked as favorite. | 0.5 per yellow cell honored | Maximize |
| S3 | Weekend-off cap: penalty if a resident has been assigned to a weekend they had marked `X` (soft unavailable). | 0.3 per violation | Minimize |
| S4 | Weekend availability cap: penalty if a resident is asked to work >2 weekends in the month (or >3 if month has 5 weekends). | 0.2 per excess weekend | Minimize |
| S5 | Year balance on weekend nights: prefer mixing year tiers (avoid two 1°-year residents in the same Prima+Coguardia notte pair). | 0.2 per same-tier pair | Minimize |

Weights live in `config/iov_weights.yaml` and can be tuned per deployment.

---

## 6. Output Schema

### 6.1 `guardie_07_2026.xlsx` (long format, 1 sheet `guardie` + 1 sheet `metadata`)

```
date | dow | shift_type            | role_required | person       | substitution_note
2026-07-04 | Sab | prima_guardia_giorno | resident      | Pittarello   | NA
2026-07-04 | Sab | coguardia_giorno     | resident      | Bertin       | NA
2026-07-04 | Sab | prima_guardia_notte  | attending     | Solda'       | replaces junior (PROSPETTO)
2026-07-04 | Sab | coguardia_notte      | resident      | Massa        | NA
2026-07-05 | Dom | prima_guardia_notte  | ONCO 2        | ONCO 2       | sentinel
...
```

### 6.2 `turni_specialisti_07_2026.xlsx` (long format)

```
date | dow | person       | activity        | location | note
2026-07-01 | Mer | Procaccio   | ambulatorio     | AMB 3    | gastro
2026-07-01 | Mer | Nichetti    | dh_mattino      | DH       | NA
2026-07-04 | Sab | Solda'      | prima_guardia_notte | reparto | replaces junior
2026-07-15 | Mer | Lonardi     | ferie           | NA       | AF
...
```

### 6.3 `turni_specializzandi_07_2026.xlsx` (long format)

```
date | dow | person      | activity              | location | tag
2026-07-01 | Mer | Bof         | reparto               | NA       | reparto
2026-07-01 | Mer | Pittarello  | clinic                | AMB 1    | LP
2026-07-04 | Sab | Pittarello  | prima_guardia_giorno  | NA       | GG
2026-07-04 | Sab | Massa       | coguardia_notte       | NA       | GN
2026-07-05 | Dom | Massa       | recupero              | NA       | SN
...
```

### 6.4 `prospetto_ambulatori_07_2026.xlsx` (grid, 1 sheet `prospetto` + 1 sheet `legend`)

```
            | Mer 1     | Gio 2     | Ven 3     | Lun 6     | …
AMB 1 mat   | Procaccio | Bergamo   | Maddalena | Intini    | …
AMB 1 pom   | …         | …         | …         | …         | …
AMB 2 mat   | …
…
AMB 4 mat   | …
DH mat      | Nichetti  | De Rosa   | …         | …         | …
```

---

## 7. UI/UX Flow (Shiny module `mod_iov_planner_*`)

### 7.1 Step 1 — Inputs panel

- Three `fileInput()` widgets, each accepting `.xlsx`.
- One `selectInput()` "Mese pianificato" (default = first month detected in any input).
- "Carica e analizza" action button.

### 7.2 Step 2 — Roster & Validazione panel

Shown after parsing succeeds. Displays:

- **Roster card** — DT table of detected residents (col: name, year, in_rotation, source). Highlight unknowns in yellow.
- **Specialists card** — DT table of detected attendings (col: name, in_guardie, clinic_only).
- **REPARTO selector** — 4 selectInputs populated from active residents; required before solve.
- **Validation report** — collapsible panels:
  - Conflicts (HARD blockers): residents in assenze but not in desiderata, ambiguous Sartori (must disambiguate), unknown year tags.
  - Warnings (SOFT): residents with >2 weekends off, residents with year=unknown, missing PROSPETTO entries.
- "Risolvi e genera turni" action button (disabled until conflicts are zero).

### 7.3 Step 3 — Solve & Output panel

- Solver status badge (`success` / `infeasible` / `time_limit_reached`).
- Objective breakdown table (equity score, yellow honors, weekend-off violations, etc.).
- Preview tabs for each of the 4 generated files (first 30 rows).
- `downloadButton()` for the bundle zip.
- "Rilascia e ricomincia" to reset state for next month.

### 7.4 Bundle layout

```
turni_07_2026.zip
├── guardie_07_2026.xlsx
├── turni_specialisti_07_2026.xlsx
├── turni_specializzandi_07_2026.xlsx
├── prospetto_ambulatori_07_2026.xlsx
└── _metadata.txt                # input hashes, solver status, weights, timestamp
```

---

## 8. Validation Strategy

### 8.1 Unit tests (per `R/iov_*.R` module)

Same TDD discipline as v1. Tests cover parser correctness against `iov/analysis/desiderata_07_2026.xlsx` (golden derived file), validator behavior on known-bad inputs, and solver feasibility on a tiny 1-week toy month.

### 8.2 Backtest (`R/iov_backtest.R`)

For each historical month in `IOV_SHIFTS_2026.xlsx` (Feb, Mar, Apr, May, Jun 2026):

1. Reconstruct the 3 inputs (PROSPETTO slice, desiderata sheet, assenze) from the available historical files (parse the PDFs into matching xlsx if needed — out of scope for this spec; manual conversion acceptable for Feb-Jun 2026).
2. Run `build_iov_model()` + `solve_iov_model()` with default weights.
3. Compare against the historical assignments cell-by-cell. Report match % per shift_type per month.

**Acceptance gate**: weighted overall match ≥ 70% across the 5 months. Lower than 70% triggers a remediation cycle (look for missing constraints).

### 8.3 Browser smoke test

After implementation:
- Launch the app locally with `APP_PASSCODE=test Rscript -e 'shiny::runApp(launch.browser = TRUE)'`.
- Upload the 3 July 2026 files.
- Verify the roster panel shows 21 residents (post-REPARTO: 17 active) + correct specialists.
- Select REPARTO = (Bof, Bivona, Bravi, Bloise).
- Solve and inspect the generated bundle.
- Confirm: 3 weekend nights (Sat Jul 4, Sun Jul 12, Sat Jul 25) have an attending in one of the night slots.
- Confirm: ONCO 2 sentinels appear where PROSPETTO says ONCO 2.

---

## 9. Known Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Backtest match < 70% → unmodelled constraints. | Medium | Iterate. Each gap surfaces a rule we missed; spec amendment + add to H/S list. |
| Desiderata file format drifts between months (e.g., column order changes, new tags). | Medium | Parser uses positional + heuristic detection (row 3 = names, dow in col A, day in col B). Validation surfaces unrecognized tags before solve. |
| Solver infeasibility under heavy constraint load. | Low-Med | Relaxation cascade: drop S5 first, then S4, then S3 if needed. Report which softs were relaxed. Hard infeasibility surfaces ompr/glpk diagnostic. |
| Ambiguous resident names (Sartori B vs Sartori E; SOLDA' vs SOLDA). | Medium | Forced disambiguation in validation panel before solve. Don't auto-merge. |
| Caposala uploads wrong month's PROSPETTO. | Low | Cross-check month consistency across the 3 inputs in validation. |

---

## 10. Implementation Phasing (preview for `writing-plans`)

| Phase | Deliverable | Est. effort |
|---|---|---|
| P-IOV-1 | Parsers (`R/iov_parse.R`) ported from `extract_desiderata_07_2026.R`, with tests against the golden derived file. | 2-3 days |
| P-IOV-2 | Roster + validation modules (`R/iov_roster.R`, `R/iov_validate.R`). | 2 days |
| P-IOV-3 | MILP build + solve (`R/iov_model.R`, `R/iov_solve.R`). All H constraints, S1+S2 only. | 4-5 days |
| P-IOV-4 | Post-processing + output writers + bundle zip (`R/iov_postprocess.R`, `R/iov_output.R`). | 2 days |
| P-IOV-5 | Shiny module (`R/shiny/iov_module.R`) + wiring into `app.R`. | 3 days |
| P-IOV-6 | Backtest harness + Feb-Jun 2026 reconstruction + tuning to ≥70%. | 3-5 days (volatile) |
| P-IOV-7 | S3, S4, S5 soft constraints + weights config. | 2 days |
| P-IOV-8 | Browser smoke + caposala UAT on real July 2026 data. | 1-2 days |

Total estimated effort: 19-26 working days. Phases 1-5 are MVP (could ship a usable planner for July 2026 in 13-15 days). Phases 6-8 are quality + tuning.

---

## 11. Open Questions (none HARD-blocking, but worth tracking)

1. Disease-group → ambulatorio room mapping is documented narratively in `IOV_RULES.md` but not as a machine-readable table. Pre-implementation task: extract that mapping into a YAML or csv.
2. The `LP` (Libera Professione) tag — is it modelled in the solver, or just preserved as an input passthrough? (Decision: passthrough for v1; LP slots are user-marked, not solver-assigned.)
3. Specialists' clinic schedule (when they're in AMB 1/2/3/4 vs DH vs reperibile) — for v1 we expect the user to set this in the assenze file or accept the solver's allocation; clarify expected level of automation here in P-IOV-3.
4. Bundle output naming: should the zip embed unit name (e.g., `turni_07_2026_onco1.zip`) for future-proofing if ONCO 2 ever gets its own planner instance?
