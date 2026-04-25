# ShiftHappens — Design Specification

**Status:** Draft for review
**Date:** 2026-04-25
**Author:** Federico Nichetti (with brainstorming via Claude Code)
**Source constraints document:** `docs/ShiftHappens_Vincoli.docx`

---

## 1. Goal & Scope

### 1.1 Goal

Build a web application that generates a monthly operating-room on-call schedule (*reperibilità sala operatoria*) for a hospital surgery group, respecting hard rules from the unit's constraints document and producing a fair distribution across operators. The application must be usable by a non-technical caposala (head nurse) and easily redeployable to other hospital units with different rules.

### 1.2 In scope (v1)

- Single Shiny web app deployed on Posit Connect Cloud, one instance per hospital unit.
- Excel-in / Excel-out workflow. The user uploads a workbook with operator roster, prior-month history, absences, soft preferences, and the target month; the app returns a workbook with the generated schedule, a per-operator summary, and diagnostics.
- MILP-based assignment engine (`ompr` + `Rglpk`) producing schedules that satisfy all hard rules and minimize a weighted soft objective.
- Per-unit YAML configuration file controlling all numeric rule knobs and unit-specific labels.
- One-shot generation flow: upload → generate → review → download. No in-app cell editing.
- App-level passcode gate (env var) for access control.
- Italian-language UI; Italian national holidays computed automatically; per-unit local holidays via YAML.
- Test suite covering parsing, validation, calendar/holiday logic, MILP build, solver outcomes, and round-trip Excel I/O.

### 1.3 Out of scope (deferred to v1.1+)

- Manual cell-locking with re-optimization around fixed assignments.
- Drag-and-drop edits or any in-app schedule modification after generation.
- Database persistence (Postgres, SQLite, or otherwise). The Excel workbook is the source of truth.
- Per-user authentication, audit logs, or roles. (Available as a Connect Cloud upgrade, no code change needed.)
- Calendar widget richer than a tabular view (e.g., `fullcalendar.js`).
- End-to-end Shiny tests (`shinytest2`).
- Internationalization beyond Italian (the structure supports a future `R/i18n_en.R`, but no English UI in v1).
- Mobile / phone layout.
- Cross-month rebalancing windows longer than 1 month (configurable via `rolling_history_months`, default 1).
- A generic abstract rule engine spanning multiple unit types in one codebase. v1 ships rules tuned for the surgery on-call domain (1° and 2° reperibile, weekday vs weekend slot structure, M3/P shift compatibility); other unit types are accommodated by editing YAML defaults — wholly different scheduling models (e.g., rotating ward shifts) would warrant a v2 redesign.

---

## 2. Locked Decisions

These were resolved during brainstorming. Each is non-negotiable for v1; changes require a spec amendment.

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Scope strategy | **Surgery-first, parameterize as we go.** Build for the surgery group with rules in YAML; generalize to other units when concrete second-team data arrives. | The constraint set is deeply domain-specific; abstracting now would mean abstracting things we don't yet understand. |
| 2 | Generation engine | **MILP** via `ompr` + `ROI` + `ROI.plugin.glpk` + `Rglpk`. Fallback: `highs`. | Verified that `libglpk-dev 5.0-1` and `libglpk40 5.0-1` are preinstalled on Connect Cloud's Ubuntu 22.04 image. MILP handles the full constraint set rigorously and yields infeasibility diagnostics for free. |
| 3 | Data persistence | **None server-side.** Stateless app; Excel workbook in/out is the only durable artifact. | Connect Cloud has no persistent writable filesystem. Hospital workflows are already Excel-based. Zero ops cost, minimal data-protection surface. |
| 4 | Interaction model | **One-shot generate.** No in-app editing in v1. | Ships fastest. Cell-locking deferred to v1.1 since MILP supports it trivially when needed. |
| 5 | Objective & infeasibility | **Four-tier soft objective** (fairness > weekend equity > preferences > smoothness). **Manual relaxation** on infeasibility — solver returns diagnostic, user adjusts inputs, reruns. | Avoids silently violating preferences. Scheduling is ultimately a human judgment call. |
| 6 | I/O format | **Excel** (`.xlsx`) with five input sheets and three output sheets. | Matches existing hospital workflow; non-technical users already know Excel. |
| 7 | Holiday handling | **Hardcoded** Italian national holidays (computed per year, including Easter via computus); per-unit local holidays via `holidays_extra` in YAML. | No reliable Italian-holidays R package; implementation is small and well-defined. |
| 8 | Access control | **App-level passcode** via env var (`APP_PASSCODE`). One Connect Cloud deployment per unit, each with its own passcode and YAML config. | Free tier; sufficient for single-unit use; clean upgrade path to Connect Cloud paid auth without code changes. |
| 9 | UI style | **bslib** with Bootstrap 5, single accent color, system typeface, no decorative imagery, weekend-row shading on the calendar. | Minimal, elegant, native-looking on every platform. Posit-recommended path. |

---

## 3. Architecture & Tech Stack

### 3.1 Topology

One R Shiny app, deployed once per hospital unit to Posit Connect Cloud. Each deployment shares the same Git repo and codebase but has its own `rules.yaml` and `APP_PASSCODE` environment variable. No shared backend, no database, no inter-deployment communication.

### 3.2 Tech stack

| Layer | Library | Purpose |
|---|---|---|
| UI framework | `shiny`, `bslib` | Reactive web UI; Bootstrap 5 layout and theming |
| Excel read | `readxl` | Parse uploaded `.xlsx` |
| Excel write | `openxlsx2` | Build output `.xlsx` with multi-sheet structure and weekend shading |
| MILP modeling | `ompr`, `ompr.roi` | Declarative DSL for the integer program |
| Solver interface | `ROI`, `ROI.plugin.glpk` | Plugin layer between `ompr` model and the solver |
| Solver backend | `Rglpk` | GLPK MIP solver; preinstalled `libglpk` on Connect Cloud |
| Solver fallback | `highs` | Self-contained HiGHS solver (vendored source, no system deps) — used only if Rglpk fails to install on a future Connect Cloud image |
| Config | `yaml` | Read `rules.yaml` |
| Dates | `lubridate` | Calendar arithmetic; weekday detection |
| Tables (UI) | `DT` | Render schedule and summary tables |
| Logging | `logger` | Structured stdout logs (Connect Cloud captures stdout) |
| Testing | `testthat` (3rd ed.) | Unit and integration tests |
| Reproducibility | `renv` | Lock dependency versions; deploy via `manifest.json` |

`pool` is **not** included. It would be needed only if path A (database persistence) were chosen; v1 has no database.

### 3.3 Data flow

```
[user]
  │ uploads .xlsx
  ▼
[mod_upload]
  │
  ▼
[io_read.R]                    parse 5 sheets → tidy tibbles
  │
  ▼
[validate.R]                   schema + cross-sheet integrity → issues tibble
  │
  ▼
[calendar.R + holidays_it.R]   target month → per-day slot table
  │
  ▼
[rules_config.R]               load YAML → rules object
  │
  ▼
[model_build.R]                ompr formulation: vars + hard constraints + objective
  │
  ▼
[model_solve.R]                ROI solve → status + assignment matrix (or infeasibility)
  │
  ▼
[model_postprocess.R]          assignment matrix → schedule + summary tibbles
  │
  ▼
[io_write.R]                   build output .xlsx (3 sheets)
  │
  ▼
[mod_schedule_view + download handler]
  │
  ▼
[user] downloads result
```

### 3.4 Why no database

Verified during brainstorming: deployed Connect Cloud apps have no writable persistent filesystem. Database persistence would require an external service (Supabase, Neon, hospital-provided Postgres) which adds ops cost, GDPR paperwork, secrets management, and an attack surface. The hospital workflow is already Excel-based; meeting users where they are minimizes adoption friction. Trade-off accepted: history accumulation depends on the user keeping the workbook current, and concurrent edits to the same workbook can clobber each other (mitigated by single-caposala-per-unit usage).

---

## 4. File Structure

Each file has one responsibility and a target ≤300 lines. Files that change together live together. Pure logic is separated from Shiny modules to keep the testable core decoupled from reactive plumbing.

```
shifthappens/
├── app.R                          # Shiny entry point
├── R/
│   ├── mod_passcode.R             # Shiny module: gate screen
│   ├── mod_upload.R               # Shiny module: file picker + validation feedback
│   ├── mod_settings.R             # Shiny module: month picker + Generate button
│   ├── mod_schedule_view.R        # Shiny module: result panel
│   ├── io_read.R                  # readxl wrappers per sheet → tibbles
│   ├── io_write.R                 # openxlsx2 writers for output sheets
│   ├── validate.R                 # schema + cross-sheet integrity
│   ├── calendar.R                 # year-month → per-day slot table
│   ├── holidays_it.R              # Italian holidays incl. Easter computus
│   ├── rules_config.R             # YAML loader + schema validation + defaults
│   ├── model_build.R              # ompr model construction
│   ├── model_solve.R              # solver call + status interpretation + diagnostics
│   ├── model_postprocess.R        # solution → schedule + summary tibbles
│   ├── ui_helpers.R               # small UI snippets (status badges, calendar render)
│   └── i18n_it.R                  # Italian UI labels
├── tests/
│   ├── testthat.R
│   └── testthat/
│       ├── test-io_read.R
│       ├── test-io_write.R
│       ├── test-validate.R
│       ├── test-calendar.R
│       ├── test-holidays_it.R
│       ├── test-rules_config.R
│       ├── test-model_build.R
│       ├── test-model_solve.R
│       └── test-model_postprocess.R
├── config/
│   ├── rules.yaml                 # default (Surgery group)
│   └── rules-oncology.yaml        # example second-unit config (when added)
├── inst/
│   └── examples/
│       ├── may2026_workbook.xlsx  # constraints-doc example as fixture
│       └── june2026_workbook.xlsx # forward-looking sample
├── docs/
│   ├── ShiftHappens_Vincoli.docx  # original constraints doc (move from repo root)
│   └── superpowers/
│       ├── specs/                 # this file
│       └── plans/                 # implementation plan (next step)
├── manifest.json                  # rsconnect deployment manifest
├── renv.lock                      # locked dependencies
├── .Rprofile                      # renv activate
├── DESCRIPTION                    # package-style metadata
└── README.md
```

### 4.1 Module boundaries

- **`io_read.R` ↔ `validate.R`** — parsing answers "did we read the cells?"; validation answers "does the data make sense across sheets?". Separating them yields clean error categorization.
- **`calendar.R` ↔ `holidays_it.R`** — Easter computus and weekday-but-holiday coercion deserve isolated tests.
- **`model_build.R` ↔ `model_solve.R` ↔ `model_postprocess.R`** — building the model is pure data transformation (testable without invoking the solver, because `ompr` lets you inspect the model object); solving is an I/O-ish call; postprocessing is pure tibble manipulation. Three files, three test files.
- **Shiny modules (`mod_*`)** are intentionally thin: they wire UI to pure R logic. Business logic lives in `R/*.R` non-Shiny files and is tested without launching Shiny.

### 4.2 Intentionally not used

- **`golem` / `leprechaun`** — adds package-skeleton ceremony without payoff for a single-app repo. Migration is mechanical if the codebase grows.
- **`shinytest2`** — deferred to v1.1.
- **`pool`** — only useful with a database, which v1 does not have.

---

## 5. Data Contracts

### 5.1 Input workbook (uploaded by user)

The workbook contains exactly five sheets. Sheet names are case-sensitive. Missing or extra sheets cause a blocking validation error.

#### 5.1.1 Sheet `operators`

One row per operator currently in roster.

| Column | Type | Required | Description |
|---|---|---|---|
| `surname` | string | yes | Used as the display label and as the operator id when `name` is absent or unique. |
| `name` | string | no | First name. Used to disambiguate operators with the same surname. |
| `role` | enum | yes | One of `senior` (1° reperibile, strumentista), `nurse_2` (junior infermiere covering 2°), `oss_2` (OSS covering 2°). |
| `part_time_pct` | integer | no, default 100 | Percentage of full-time hours. Drives the optional pro-rata adjustment to monthly cap (see §6.4). |
| `active_from` | date | no, default `1900-01-01` | First date the operator is in roster. |
| `active_to` | date | no, default `9999-12-31` | Last date the operator is in roster. |

The combination `(surname, name)` must be unique. The internal `operator_id` is `surname` if no other operator shares it, otherwise `surname_name`.

#### 5.1.2 Sheet `history`

One row per past on-call assignment used for cross-month rebalancing. Window controlled by `rolling_history_months` in `rules.yaml`.

| Column | Type | Required | Description |
|---|---|---|---|
| `date` | date | yes | Date of the on-call assignment. |
| `slot` | enum | yes | One of `weekday_night`, `weekend_day`, `weekend_night`, `holiday_day`, `holiday_night`. |
| `role_slot` | enum | yes | `first` or `second`. |
| `operator_id` | string | yes | Must match an operator in the `operators` sheet (resolution rule above). |

History rows whose `date` falls outside the rolling window are ignored. History rows for operators no longer in roster (cessation, transfer) are ignored for rebalancing but kept for the `summary` output.

#### 5.1.3 Sheet `absences`

One row per absence interval. Whole-day granularity only in v1.

| Column | Type | Required | Description |
|---|---|---|---|
| `operator_id` | string | yes | Resolves against `operators`. |
| `date_from` | date | yes | First absent date (inclusive). |
| `date_to` | date | yes | Last absent date (inclusive). Must be ≥ `date_from`. |
| `type` | enum | yes | One of `L104`, `CSR`, `study`, `vacation`, `sick`, `other`. Informational; all types block all slot assignments equally in v1. |

#### 5.1.4 Sheet `preferences`

One row per recurring soft (or hard) preference per operator. Fovanna's three rules from the constraints doc encode as three rows here.

| Column | Type | Required | Description |
|---|---|---|---|
| `operator_id` | string | yes | Resolves against `operators`. |
| `weekday` | integer 1–7 | no | 1 = Monday, …, 7 = Sunday. Blank = applies to every weekday. |
| `slot_type` | enum | no | `day` or `night`. Blank = applies to every slot. |
| `polarity` | enum | yes | `avoid` or `prefer`. |
| `hard` | boolean | no, default FALSE | If TRUE, treat as a hard constraint (operator never assigned matching slot). If FALSE, treat as a soft term in the objective. |

Example for Fovanna:

| operator_id | weekday | slot_type | polarity | hard |
|---|---|---|---|---|
| Fovanna | 4 | (blank) | avoid | FALSE |
| Fovanna | 5 | (blank) | avoid | FALSE |
| Fovanna | 6 | day | avoid | FALSE |

#### 5.1.5 Sheet `month`

Two-cell sheet. Cell `A1` contains the literal header `month`; cell `A2` contains the target year-month in `YYYY-MM` format (e.g., `2026-06`). This shape lets `readxl::read_excel(sheet = "month")` parse it as a one-row tibble with column `month`. The value must be ≥ the current calendar month at upload time.

### 5.2 Output workbook (downloaded after generation)

#### 5.2.1 Sheet `schedule`

Mirrors the layout from the constraints doc §3 (May 2026 example).

| Column | Type | Description |
|---|---|---|
| `date` | date | Day of the month. |
| `weekday` | string | Italian weekday letter: `L`, `M`, `M`, `G`, `V`, `S`, `D`. |
| `1° reperibile` | string | Operator surname for weekdays; `Surname1 / Surname2` for weekends/holidays (day / night). |
| `2° reperibile` | string | Same convention. |

Rows for Saturday, Sunday, and holidays are shaded (`#f7f7f7` background) to match the constraints doc.

#### 5.2.2 Sheet `summary`

One row per operator active during the target month.

| Column | Type | Description |
|---|---|---|
| `operator_id` | string | Display id. |
| `role` | enum | `senior` / `nurse_2` / `oss_2`. |
| `n_first` | integer | On-call assignments as 1° in target month. |
| `n_second` | integer | On-call assignments as 2°. |
| `n_weekend` | integer | Weekend slot count (any role). |
| `n_holiday` | integer | Holiday slot count (any role). |
| `total` | integer | `n_first + n_second`. |
| `carry_in_window` | integer | Total from the rolling history window (excluding target month). |
| `delta_vs_mean` | numeric | `total + carry_in_window` minus the role-group mean of the same. Positive = above average; negative = below. Used by the caposala to sanity-check fairness. |

#### 5.2.3 Sheet `diagnostics`

Free-form diagnostic information for the run.

| Row label | Value |
|---|---|
| `solver_status` | `optimal` / `feasible` / `infeasible` / `timeout`. |
| `runtime_seconds` | numeric |
| `objective_value` | numeric (if solved) |
| `relaxed_soft_preferences` | List of `operator_id` × rule-row-index that were violated, with weight contribution. |
| `infeasibility_diagnosis` | If `infeasible`, the relaxation suggestion (see §7.3). |

---

## 6. YAML Rules Configuration

### 6.1 File format

The active config is `config/rules.yaml`. The path can be overridden by env var `RULES_CONFIG_PATH` (used at deployment time to point at `config/rules-oncology.yaml`, etc.).

### 6.2 Schema

```yaml
unit:
  name: "Gruppo Chirurgia"           # displayed in header
  locale: "it"                       # reserved for future i18n
roles:
  primary: "senior"                  # which operator role can take 1°
  secondary: ["nurse_2", "oss_2"]    # which roles can take 2°
limits:
  senior_max_per_month: 7
  min_free_weekends_per_month: 2
  weekday_min_rest_days: 1
  post_weekend_min_rest_days: 1      # answers constraints-doc open Q §4.1
  rolling_history_months: 1          # locked: 1
fairness_weights:
  monthly_total: 100
  weekend_holiday: 50
  preference: 20
  smoothness: 5
solver:
  time_limit_seconds: 30
  fallback: "highs"                  # used only if Rglpk unavailable at runtime
holidays_extra:
  - { name: "S. Patrono",  date: "12-04" }   # MM-DD; per-unit local holidays
  - { name: "Local feast", date: "06-13" }
ui:
  primary_color: "#2c5f7e"
  table_density: "compact"
```

### 6.3 Loading rules

`rules_config.R::load_rules(path)` reads the YAML, validates against the schema (typed errors for missing required keys, wrong types, out-of-range values), and returns a flat list. Defaults are merged on top of user-supplied values; missing optional keys fall back to defaults silently.

### 6.4 Part-time accommodation

Per constraints doc §5: part-time operators "in theory have one fewer on-call per month, but in practice adapt to fill the rota". v1 implements the **flexibility-first** behavior — `part_time_pct` is informational and surfaces in the `summary` sheet's `delta_vs_mean`, but does **not** automatically reduce that operator's allocation. Future v1.1 may add a `part_time_strict: true` YAML knob to enforce a pro-rata cap.

---

## 7. Scheduling Logic

### 7.1 Calendar build

Given target month `Y-M` and the YAML's `holidays_extra`:

1. Enumerate every day of the month.
2. For each day compute: `weekday` (1–7), `is_weekend` (Sat/Sun), `is_holiday` (in Italian national list or `holidays_extra`).
3. Collapse weekday-but-holiday into the weekend slot structure (per constraints doc §4.7: when a holiday falls on Thu/Fri/Sat, university is closed → Fovanna available; the day gets four 12-hour slots, not one weekday-night slot).
4. Output: one tibble row per day with column `slots` (list-col) containing either:
   - Weekday non-holiday: `[(role=1°, kind=weekday_night), (role=2°, kind=weekday_night)]`.
   - Weekend or holiday: `[(role=1°, kind=day), (role=1°, kind=night), (role=2°, kind=day), (role=2°, kind=night)]`.

### 7.2 MILP formulation

#### 7.2.1 Decision variables

```
x[op, d, s, r] ∈ {0, 1}
```

where:
- `op` ∈ operators active on day `d`,
- `d` ∈ days in target month,
- `s` ∈ slot kinds present on day `d` (1 for weekday, 2 day-vs-night for weekend/holiday),
- `r` ∈ {1°, 2°}.

Variables are created only for valid `(op, d, s, r)` combinations (e.g., no `r = 1°` for `op` with role ≠ senior; no slots on operator's absence dates). This keeps the model size tight.

#### 7.2.2 Hard constraints

| ID | Description | Formal expression (informal) |
|---|---|---|
| H1 | Coverage | For every (d, s, r) slot: `sum over op of x[op, d, s, r] = 1`. |
| H2 | Role eligibility (1°) | `x[op, d, s, 1°] = 0` whenever `op.role ≠ senior`. (Encoded by skipping variable creation.) |
| H3 | Role eligibility (2°) | Variables for `r = 2°` are created for **every** operator regardless of role. Seniors may cover 2° (per constraints doc §1.2). A senior who covers a 2° slot counts toward the **2° group's** fairness pool, not the senior group's, so the model is naturally biased toward keeping seniors on 1° unless coverage requires otherwise. |
| H4 | Absence | `x[op, d, *, *] = 0` for every (op, d) such that d ∈ op's absence intervals. |
| H5 | Weekday rest | `sum over (s,r) of x[op, d, s, r] + sum over (s,r) of x[op, d+1, s, r] ≤ 1` for every operator and every consecutive weekday pair (no two consecutive weekday on-calls). |
| H6 | Post-weekend rest | If day `d` is the last weekend day or holiday and `d+1` is a weekday: `(weekend assignment on d) + (weekday assignment on d+1) ≤ 1`, parameterized by `post_weekend_min_rest_days`. |
| H7 | No 24h consecutive on weekends | Forbid the three combinations from constraints doc §4.4: `Sat-day + Sat-night`, `Sat-night + Sun-day`, `Sun-day + Sun-night`. For each operator and each weekend, add a constraint `x[op, sat, day, *] + x[op, sat, night, *] ≤ 1`, etc. |
| H8 | Min free weekends | For each operator: `sum over weekends of (any assignment that weekend) ≤ total_weekends_in_month - min_free_weekends_per_month`. |
| H9 | Senior monthly cap | For each senior: `sum over d, s of x[op, d, s, 1°] ≤ senior_max_per_month`. |
| H10 | Hard preferences | For each preference row with `hard = TRUE`: `x[op, d, s, *] = 0` for matching (d, s). |
| H11 | Sunday-night → Monday-afternoon — implicit | Enforced as part of H5/H6: a Sunday-night assignment plus a Monday assignment is forbidden, and the constraints doc §4.3's "Monday afternoon shift" is a downstream daily-shift consequence outside the on-call planner's remit (the regular ward shift planner consumes our output and applies it). |

The "compatibility with the day shift M3/P" rules (constraints doc §4.3, §4.5) are documented for the consumer of the schedule. The on-call planner does not assign M3 / P shifts; those follow mechanically from the on-call assignment per the documented pattern, applied by whoever produces the daily ward shift sheet.

#### 7.2.3 Soft objective

Minimize the weighted sum:

```
Z =   w_total       * S_total
    + w_we_holiday  * S_we_holiday
    + w_preference  * S_preference
    + w_smoothness  * S_smoothness
```

Weights from `fairness_weights` in YAML (defaults: 100, 50, 20, 5).

- **`S_total`** — dispersion of monthly total assignments within each role group. Linearized via auxiliary variables `t_max_g` and `t_min_g` per role group `g`, with `S_total = sum_g (t_max_g - t_min_g)`. The optimizer minimizes the spread.
- **`S_we_holiday`** — sum of |operator's (target-month weekend+holiday count + carry-in window) − group mean| linearized via auxiliary deviation variables.
- **`S_preference`** — for each soft (`hard=FALSE`) preference row, if matching variable `x = 1`, add 1 to `S_preference`. (Solver minimizes total preference violations.)
- **`S_smoothness`** — for each operator, for each pair of days `(d, d+2)` and `(d, d+3)` (3-day window beyond the H5 hard rule), add a small penalty if both have assignments.

### 7.3 Solver invocation and outcomes

```r
solution <- solve_model(model, with_ROI(solver = "glpk", verbose = FALSE,
                                         control = list(tm_limit = time_limit_ms)))
```

Three terminal states:

1. **`optimal` / `feasible`** — `solver_status_code(solution)` indicates success. Pass to postprocessor.
2. **`infeasible`** — solver proves no feasible assignment exists. Run **infeasibility diagnosis**:
   - Drop H8 (free-weekend rule) and re-solve. If feasible → suggest relaxing weekend cap.
   - Else, drop H9 (senior cap) and re-solve. If feasible → suggest raising `senior_max_per_month`.
   - Else, drop H10 (hard preferences) and re-solve. If feasible → suggest demoting one preference to soft.
   - Else → suggest reviewing absences for over-coverage of any single day.
   - Whichever relaxation makes it feasible is reported in `diagnostics.infeasibility_diagnosis`. The original model is **not** silently relaxed; the user must re-upload with adjustments.
3. **`timeout`** — solver did not return within `time_limit_seconds`. Treated as practically-infeasible: surface message "Solver took too long. Consider reducing fairness weights or removing edge-case absences."

---

## 8. Italian Holidays

### 8.1 Fixed national holidays

| Date | Name |
|---|---|
| 01-01 | Capodanno |
| 01-06 | Epifania |
| 04-25 | Festa della Liberazione |
| 05-01 | Festa dei Lavoratori |
| 06-02 | Festa della Repubblica |
| 08-15 | Ferragosto |
| 11-01 | Tutti i Santi |
| 12-08 | Immacolata Concezione |
| 12-25 | Natale |
| 12-26 | Santo Stefano |

### 8.2 Movable holidays — Pasqua and Pasquetta

Computed via the standard Gauss / Meeus computus algorithm for Western Easter. Pasquetta = Easter + 1 day.

`holidays_it.R::italian_holidays(year)` returns a tibble of `(date, name)` for the given year. Tested against known dates 2025–2030.

### 8.3 Per-unit holidays

`holidays_extra` in YAML adds saint days or local feasts. Format `MM-DD`, repeated each year. Rare moveable local feasts (e.g., a saint patron tied to Easter) — not supported in v1; if needed, hardcode in YAML for each year.

### 8.4 Weekday-but-holiday handling

When an Italian holiday falls on a weekday, the day's slot structure becomes the weekend structure (4 slots: 1°-day, 1°-night, 2°-day, 2°-night). Constraints doc §4.7 confirms this convention (Fovanna: "quando giovedì / venerdì / sabato coincidono con una festività — Fovanna può essere normalmente reperibile"). The `is_holiday` column flows through to the H7 (no 24h consecutive) and `S_we_holiday` (weekend+holiday equity) logic.

---

## 9. Validation Rules

`validate.R::validate_inputs(parsed)` returns a tibble `(severity, sheet, row, column, message)`. Severities:

- **`error`** — blocks generation. UI disables the Generate button.
- **`warning`** — does not block; surfaced in the UI for user awareness.

### 9.1 Errors (blocking)

- Missing required sheet.
- Missing required column in any sheet.
- Type coercion failure (e.g., `date_from` not a date).
- `month` not parseable as `YYYY-MM`.
- `month` < current calendar month.
- `operators` has < 1 senior or < 1 secondary operator.
- Any `history.operator_id` or `absences.operator_id` not resolvable in `operators`.
- `absences.date_from > date_to`.
- Any `preferences.weekday` outside 1–7 or `slot_type` outside `day`/`night`/blank.
- YAML config: missing required key, wrong type, out-of-range numeric.

### 9.2 Warnings (non-blocking)

- A senior with zero history rows in the rolling window.
- A preference row that cannot match any slot in the target month (e.g., Fovanna's Saturday-day rule when the target month has no non-holiday Saturdays — pathological but possible for very short windows).
- An operator listed in `operators` but with no presence either as senior or secondary in any history or absence row (suggests a typo).
- Total absences cover ≥ 50% of any role group on any single day (unlikely to be infeasible but worth flagging).

---

## 10. Testing Strategy

### 10.1 Layer 1 — Pure-function unit tests

`testthat` (3rd ed.). No Shiny, no solver in the hot path.

- **`test-holidays_it.R`** — known Easter dates 2025–2030; fixed-date holidays present; weekday-but-holiday flag flips.
- **`test-calendar.R`** — months with 4 weekends vs 5 weekends; February (leap and non-leap); month containing 1 maggio; month containing Pasqua + Pasquetta.
- **`test-rules_config.R`** — valid YAML loads; missing required keys raise typed errors; defaults merge correctly; invalid types raise typed errors.
- **`test-validate.R`** — each error path triggers the expected severity; happy path returns no issues.
- **`test-io_read.R` + `test-io_write.R`** — round-trip: write tibble → re-read → assert equality. Includes weekend-shading round-trip.
- **`test-model_postprocess.R`** — known assignment matrix → known schedule + summary tibbles, including the `Surname1 / Surname2` weekend formatting.

### 10.2 Layer 2 — Solver integration tests

Tiny synthetic instances (≤10 operators, ≤7 days) so the suite stays under 10 s.

- **Smoke test:** 3 seniors + 3 juniors over 7 weekdays, no absences → solver returns optimal; coverage constraint satisfied.
- **Hard constraint trigger (H4):** feasible base + an absence covering all seniors on day 3 → solver returns infeasible; diagnostic identifies day 3.
- **Fairness:** 4 seniors over 8 weekday slots → assignment is exactly 2 each (degenerate fairness; easy assertion).
- **Preference relaxation:** preference row set as `hard=TRUE` and infeasible only because of it → flipping `hard=FALSE` makes it feasible; preference appears in `S_preference > 0` and in the relaxation report.
- **Golden test:** the May 2026 workbook from the constraints doc → solver produces *some* feasible schedule. We do **not** assert byte-equality with the human-made schedule; we assert every documented hard constraint is respected.

### 10.3 Layer 3 — Shiny end-to-end (deferred)

`shinytest2` smoke test: launch app, upload `inst/examples/may2026_workbook.xlsx`, click Generate, assert download offered. Deferred to v1.1 — reactivity issues are rare in a stateless app this small, and the cost of the `shinytest2` infra (chromote, phantomjs) is not justified at v1.

### 10.4 Coverage target

≥80% on `R/*.R` non-Shiny files. Shiny modules (`mod_*.R`) excluded — they're trivially thin.

### 10.5 CI

GitHub Actions on push and PR:

1. Restore from `renv.lock`.
2. `R CMD check`.
3. `testthat::test_local()`.

Run on `ubuntu-22.04` to match Connect Cloud's runtime exactly. Locks deployment-environment risk at PR time.

---

## 11. UI / UX

### 11.1 Single-page state machine

The app has six states. Transitions are driven by user actions and reactive results.

```
[State 0] Passcode prompt
   │
   │ correct passcode
   ▼
[State 1] Empty / upload prompt
   │
   │ file uploaded + parsed + validated
   ▼
[State 2] Parsed: input summary + validation panel + Generate button
   │
   │ click Generate
   ▼
[State 3] Generating (solver running)
   │
   │ solver returns
   ├──── feasible ────────► [State 4] Generated: schedule + summary + download
   │
   └──── infeasible ──────► [State 5] Infeasible: diagnostic + suggested relaxations
                                   │
                                   │ user adjusts inputs and re-uploads
                                   ▼
                            [State 1]
```

### 11.2 Layout

`bslib::page_sidebar()`:

- **Sidebar (left):** unit name (from YAML), file upload, target-month picker (defaulted to current month + 1), Generate button, Start-over link.
- **Main panel (right):** state-driven content.
  - State 1: empty illustration (just text — no image).
  - State 2: collapsible "Input summary" card + validation panel.
  - State 3: spinner + "Sto generando…" text.
  - State 4: status badge + calendar table + summary table + diagnostics accordion + Download button.
  - State 5: red banner + diagnostic text + bullet list of suggested relaxations + "Modifica input" link.

### 11.3 Styling

```r
bs_theme(
  version = 5,
  primary = config$ui$primary_color,    # default "#2c5f7e"
  base_font = font_collection("system-ui", "-apple-system", "Segoe UI"),
  font_scale = 1.0
)
```

Principles:

- One accent color, configurable per unit via YAML.
- System typeface stack — fast, native-looking.
- No icons except functional ones (upload, download).
- No decorative imagery.
- Calendar weekend rows shaded `#f7f7f7`.
- Status: one prominent banner per state.
- No animation beyond Bootstrap defaults.

### 11.4 Tables

`DT::datatable()` with options `pageLength = 31, dom = 't'` (no length menu, no info, no filter on the calendar; per-operator summary keeps default sort). Weekend shading via `formatStyle()`.

### 11.5 Internationalization

All UI strings in `R/i18n_it.R`:

```r
i18n_it <- list(
  app_title = "ShiftHappens",
  upload_label = "Carica il file Excel",
  generate = "Genera",
  generating = "Sto generando…",
  download = "Scarica .xlsx",
  ...
)
```

Future English support = drop-in `R/i18n_en.R` selected by `unit.locale` in YAML. Not implemented in v1.

### 11.6 Responsiveness

Desktop-first (assumed primary target). Tablet works (page_sidebar collapses gracefully). Phone is not a target — uploading workbooks on a phone is bad UX regardless.

---

## 12. Deployment

### 12.1 Per-unit deployment recipe

For each new hospital unit:

1. **Copy** `config/rules.yaml` → `config/rules-<unit>.yaml`. Edit values.
2. **Add** any unit-specific holidays under `holidays_extra`.
3. **Set** `unit.name` to the unit's display name.
4. **Optionally** override `ui.primary_color` to a unit-specific accent.
5. **Publish** to Connect Cloud as a new app instance, with environment variables:
   - `RULES_CONFIG_PATH` = `config/rules-<unit>.yaml`
   - `APP_PASSCODE` = the unit's shared passcode
6. **Share** the URL + passcode with the unit's caposala.

### 12.2 Repository layout

One Git repo, one `main` branch, multiple deployments. Each deployment is just a Connect Cloud "app" pointing at the same repo with different env vars. No branches per unit. Release tags (`v1.0`, `v1.1`, etc.) mark coordinated upgrade points.

### 12.3 manifest.json

`rsconnect::writeManifest()` produces `manifest.json` from the current `renv.lock`. Committed to the repo. Connect Cloud uses this to reproduce the environment without runtime `install.packages()` calls.

### 12.4 Logging

`logger::log_info()` for app-lifecycle events (start, file uploaded, solver started, solver finished, file downloaded). `logger::log_error()` for caught exceptions. Logs go to stdout, captured by Connect Cloud's log viewer.

### 12.5 Secrets

- `APP_PASSCODE` is the only secret. Set in Connect Cloud's app settings, never committed.
- No database credentials, no API keys.

---

## 13. Open Items Parameterized in YAML

The constraints doc has several open questions. v1 answers each via a YAML default. The caposala can override per deployment without code changes.

| Constraints-doc question | Status in v1 | YAML key | Default |
|---|---|---|---|
| §1.2: OSS vs nurse equivalence for 2° | Treated as equivalent in v1. | `roles.secondary` | `["nurse_2", "oss_2"]` (both eligible for 2°) |
| §4.1: Stagger after weekend on-call | Yes, ≥1 day rest. | `limits.post_weekend_min_rest_days` | `1` |
| §4.2: Total monthly cap beyond weekend rule | Yes, senior cap. | `limits.senior_max_per_month` | `7` |
| §5.1: Rebalance window length | Last 1 month. | `limits.rolling_history_months` | `1` |
| §5: Part-time strict pro-rata | Flexibility-first (informational only). | (future) `limits.part_time_strict` | `false` (implicit; not yet a key) |

Open questions explicitly **out of scope for v1** and not yet parameterized: substitutions (constraints doc §6), seniority promotion criteria (§7).

---

## 14. Versioning & Future Work

### 14.1 v1.1 backlog

- Cell-locking with re-optimization (MILP can fix specific decision variables to 1).
- Richer calendar widget (e.g., `fullcalendar.js` via `htmlwidgets`).
- `shinytest2` end-to-end tests.
- `part_time_strict` YAML knob.
- Substitutions sheet (out-of-band swap requests applied post-generation).
- English UI via `i18n_en.R`.

### 14.2 v2 candidates

- True cross-unit codebase generalization (abstract rule engine, multi-tenant).
- Database persistence with per-user audit (Connect Cloud paid tier or external Postgres).
- Mobile-first companion view for operators to see their own assignments.

---

## 15. Glossary

| Term | Meaning |
|---|---|
| **Reperibilità** | Italian for on-call duty. |
| **1° / 2° reperibile** | First / second on-call operator for a given slot. 1° is always a senior strumentista; 2° supports. |
| **Strumentista** | Scrub nurse trained to assist in surgery. |
| **OSS** | *Operatore Socio-Sanitario* — healthcare support worker, less specialized than a nurse. |
| **Caposala** | Head nurse / unit coordinator. The user of this app. |
| **M3** | Morning ward shift, 07:30–15:00. |
| **P** | Afternoon ward shift, 15:00–19:30. |
| **Slot** | A coverable on-call period: weekday-night, weekend-day, weekend-night, holiday-day, holiday-night. |
| **Senior** | Operator eligible to cover 1°. |
| **Junior** | Operator covering only 2°. |
| **MILP** | Mixed-Integer Linear Programming — the optimization technique used by the engine. |
| **Computus** | Algorithm to compute the date of Easter for a given year. |
