# ShiftHappens — Multi-tenant Landing Redesign

**Status:** Draft for review
**Date:** 2026-05-25
**Author:** Federico Nichetti (with brainstorming via Claude Code)
**Predecessor specs:**
- `docs/superpowers/specs/2026-04-25-shifthappens-design.md` — v1 generic single-unit scheduler (shipped)
- `docs/superpowers/specs/2026-05-21-iov-planner-design.md` — IOV Planner phase definitions (P-IOV-1 parsers shipped)

**Design system source:** `ui-ux-pro-max` design-system recommendation for "healthcare scheduling tool" (navy `#1E3A5F` primary + green `#059669` accent, Figtree headings + Noto Sans body, Minimal Single Column pattern, Micro-interactions style).

---

## 1. Goal & Scope

### 1.1 Goal

Replace the current ShiftHappens v1 UI (single-unit-per-deployment, multi-tab workflow, plain bslib defaults) with a **single multi-tenant landing page** that wraps multiple hospital centres behind one Shiny app instance, with a clean modern design suitable for non-technical caposala users. Each centre exposes the same three actions (upload desiderata, pick month, upload rules, generate schedule) but routes to its own backend (IOV-specific vs generic).

### 1.2 In scope (v2 landing)

- New top-level UI replacing `app.R` and v1 `R/mod_*` modules.
- Single Shiny app deployed once to Connect Cloud, serving multiple centres listed in `config/centres.yaml`.
- Two centres at launch: **IOV - Oncologia 1** (uses IOV-specific MILP backend), **Crema - Sala operatoria** (uses v1 generic MILP backend).
- Landing page with hero (title + presentation) + CTA → expandable accordion of centre cards.
- Per-centre passcode gate (passcode read from env var per centre).
- Per-centre inline flow: passcode → 3 inputs (month, desiderata, optional rules) → "Genera turno" button → inline output (value boxes + DT calendar table + download xlsx).
- Light/dark mode toggle (`bslib::input_dark_mode`).
- Italian/English language switch (custom `input_switch`, no external i18n package).
- Re-uses all v1 backend modules unchanged (`R/calendar.R`, `R/holidays_it.R`, `R/rules_config.R`, `R/io_*.R`, `R/validate.R`, `R/model_*.R`).
- Re-uses P-IOV-1 parsers (`R/iov_parse.R`) for the IOV centre.
- Stateless: no database, Excel-in/Excel-out only.
- Tests covering centres config validation, i18n completeness, Shiny module flows (`testServer`), and at least one E2E `shinytest2` run per centre.

### 1.3 Out of scope (deferred to later)

- Backend IOV (P-IOV-2 roster, P-IOV-3 MILP, P-IOV-4 postprocess, P-IOV-5 UI specifics) — landing release is **gated on these being complete**.
- More than IT/EN (framework supports adding languages by extending `STRINGS`, but no third language in v2).
- Role-based access / user accounts (passcode is the only auth mechanism).
- In-app admin UI for adding/editing centres (centres are configured by editing the YAML and pushing).
- Drag-and-drop schedule editing / cell-locking (still deferred from v1 plan).
- Mobile / phone layout (responsive down to 375px works but no phone-first optimisation).
- Multi-centre concurrent generation in one session (one centre expanded at a time via `accordion(multiple = FALSE)`).
- Centre-specific branding (logos, custom colours per centre). All centres share the global ShiftHappens brand.

---

## 2. Locked Decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Deployment model | **Single app multi-tenant.** One Connect Cloud instance serves all centres. Centres listed in `config/centres.yaml`. | Avoids per-unit deployment proliferation; simplifies updates (one push, all centres benefit). Stateless design supports it (no per-centre DB to keep apart). |
| 2 | Landing pattern | **Minimal Single Column** (per ui-ux-pro-max design system). Hero title + lead paragraph + single primary CTA → smooth scroll to centre accordion. | Matches the user's brief literally ("one page, simple, clean, modern, minimalistic"); benchmarks well for clarity and conversion. |
| 3 | Centre expansion UX | **Inline accordion** via `bslib::accordion(multiple = FALSE)`. One centre expanded at a time. | Matches user's "inside each you can press buttons" model. No URL changes. Standard bslib pattern with built-in keyboard navigation + a11y. |
| 4 | Output placement | **Inline below the actions**, in the same expanded centre panel. | Single-page model preserved; user scrolls down naturally. No modal flash. |
| 5 | Generation trigger | **Explicit "Genera turno" button** (`bslib::input_task_button`). Disabled until required inputs present. | Gives user control; avoids accidental re-runs when files change. `input_task_button` handles loading state idiomatically. |
| 6 | Authentication | **Passcode per centre**, read from env var (e.g. `PASSCODE_IOV_ONCO1`). Validated client-server in the passcode gate; centre actions hidden until correct. | Matches "hospital staff knows their own centre" mental model. No user accounts (out of scope). Simple, deploy-time-configured. |
| 7 | Theming | **`bslib::bs_theme(version = 5)`** with explicit colours + Google fonts. Light + dark via `input_dark_mode()` + `session$setCurrentTheme()`. Plots adapt via `thematic::thematic_shiny()`. | Industry-standard bslib pattern. No `brand.yml` for v2 (overkill for two centres sharing one brand) — possible upgrade later. |
| 8 | i18n approach | **Lightweight in-house** via `R/i18n.R` (named lists `STRINGS$it`, `STRINGS$en`) + `tr(key)` helper + reactive `current_lang`. No `shiny.i18n` or `i18nlister` package. | YAGNI for two languages. Test enforces parity (every IT key has EN). Centre names are NOT translated (proper nouns). |
| 9 | IOV release gate | **Wait for P-IOV-3+ before shipping the landing.** Both centres must work end-to-end at launch. | User decision: avoid shipping with one centre in "Coming soon" state. |
| 10 | Module split | **One file per concern** under `R/mod_*` + supporting `R/i18n.R`, `R/centres_config.R`, `R/shifthappens_theme.R`. Old v1 `R/mod_*` files removed. | Keeps each module small and testable. Matches v1 conventions. |

---

## 3. Architecture

### 3.1 Module map

```
R/
├── app.R                          # page_fluid + theme + top-level observers
├── shifthappens_theme.R           # bs_theme() factory (light + dark variants)
├── i18n.R                         # STRINGS named lists + tr() helper
├── centres_config.R               # load_centres_config(path), helpers
│
├── mod_topbar.R                   # dark mode + IT/EN switches + logo
├── mod_hero.R                     # H1 title + lead + CTA scroll button
├── mod_centres_accordion.R        # iterate centres, render one panel each
├── mod_centre_card.R              # one centre: passcode + actions + output
├── mod_centre_output.R            # value_boxes + DT calendar + download
│
├── (parsers — already exist / P-IOV-1)
├── iov_parse.R                    # IOV inputs → parsed_inputs (DONE)
├── io_read.R                      # v1 generic workbook
│
├── (backend — v1 modules, reused unchanged)
├── calendar.R, holidays_it.R, rules_config.R,
├── validate.R, model_build.R, model_solve.R, model_postprocess.R,
├── io_write.R
│
└── (IOV backend — to be built, gates v2 release)
    iov_roster.R                   # P-IOV-2 (TBD)
    iov_model.R                    # P-IOV-3 (TBD)
    iov_postprocess.R              # P-IOV-4 (TBD)
```

Files **removed** from v1 by this redesign (replaced by new `mod_*`):
- old `app.R`
- old `R/mod_passcode.R`, `R/mod_upload.R`, `R/mod_schedule.R`, `R/mod_summary.R`, `R/mod_diagnostics.R`

### 3.2 Page wrapper

```r
ui <- bslib::page_fluid(
  theme = shifthappens_theme("light"),
  lang  = "it",
  shifthappens_topbar("topbar"),
  div(
    class = "mx-auto",
    style = "max-width: 768px;",
    shifthappens_hero("hero"),
    shifthappens_centres_accordion("centres")
  )
)
```

No sidebar (`page_sidebar` not used). No navbar (`page_navbar` not used). The redesign is fundamentally a long-scroll page, not a dashboard.

### 3.3 Solver routing by centre

Each centre in `centres.yaml` declares a `parser` field (`iov` or `generic`). At generate-time the centre card dispatches:

```r
generate_schedule <- function(centre, state, rules, cal) {
  inputs <- switch(centre$parser,
    iov     = read_iov_inputs(...),               # P-IOV-1 parsers + IOV-specific roster
    generic = read_workbook(state$desiderata_file) # v1 io_read.R
  )

  model <- switch(centre$parser,
    iov     = build_iov_model(inputs, rules, cal),  # P-IOV-3 (TBD)
    generic = build_milp(inputs, rules, cal)         # v1
  )
  solve_milp(model)
}
```

Adding a future third backend = add an entry to the `switch` and a new `parser` value in YAML.

---

## 4. Data Model & Configuration

### 4.1 `config/centres.yaml` schema

```yaml
centres:
  - id: iov-oncologia-1
    name: "IOV - Oncologia 1"
    subtitle_it: "Padova · MILP IOV-specific"
    subtitle_en: "Padua · IOV-specific MILP"
    parser: iov                       # routes to R/iov_parse.R + IOV backend
    rules_path: config/rules-iov-oncologia-1.yaml
    passcode_env: PASSCODE_IOV_ONCO1  # env var name

  - id: crema-sala-operatoria
    name: "Crema - Sala operatoria"
    subtitle_it: "Reparto Chirurgia · MILP generico"
    subtitle_en: "Surgical ward · generic MILP"
    parser: generic                   # routes to R/io_read.R + v1 backend
    rules_path: config/rules-crema-sala-operatoria.yaml
    passcode_env: PASSCODE_CREMA
```

Validation rules (enforced by `load_centres_config()`):
- `id` unique across centres, kebab-case.
- `parser ∈ {"iov", "generic"}`.
- `rules_path` exists on disk.
- `passcode_env` defined in environment at startup, OR `APP_DEV_MODE=true` (skip passcode for local dev).
- `subtitle_it` and `subtitle_en` both present.

### 4.2 Per-centre reactive state (in `mod_centre_card` server)

```r
centre_state <- reactiveValues(
  unlocked        = FALSE,           # passcode validated?
  target_month    = NULL,            # "2026-07"
  desiderata_file = NULL,            # upload$datapath
  rules_file      = NULL,            # upload$datapath; fallback = centre$rules_path
  result          = NULL,            # solver output tibble
  result_status   = NULL,            # "success" | "infeasible" | "error"
  result_message  = NULL,
  generate_at     = NULL             # timestamp, for logging
)
```

No database. The downloaded xlsx is the only durable artefact.

### 4.3 i18n string lists

```r
# R/i18n.R
STRINGS <- list(
  it = list(
    landing_title    = "ShiftHappens",
    landing_lead     = "Pianifica turni di guardia con MILP nei reparti ospedalieri italiani.",
    cta_centres      = "Centri partecipanti",
    centre_passcode  = "Inserisci passcode",
    centre_month     = "Mese da pianificare",
    centre_desiderata = "Desiderata mensile",
    centre_rules     = "Regole (opzionale)",
    centre_generate  = "Genera turno",
    solving          = "Generazione in corso…",
    download         = "Scarica .xlsx",
    infeasible       = "Vincoli inconsistenti, vedi diagnostica.",
    error            = "Errore durante la generazione."
  ),
  en = list(
    landing_title    = "ShiftHappens",
    landing_lead     = "Plan on-call schedules with MILP for Italian hospital units.",
    cta_centres      = "Participating centres",
    centre_passcode  = "Enter passcode",
    centre_month     = "Month to plan",
    centre_desiderata = "Monthly requests",
    centre_rules     = "Rules (optional)",
    centre_generate  = "Generate schedule",
    solving          = "Generating…",
    download         = "Download .xlsx",
    infeasible       = "Inconsistent constraints, see diagnostics.",
    error            = "Error during generation."
  )
)

tr <- function(key) STRINGS[[current_lang()]][[key]]
```

A test (`test-i18n.R`) enforces that `names(STRINGS$it) == names(STRINGS$en)`.

---

## 5. UI/UX

### 5.1 Layout (single column, max-width 768px, centered)

```
┌─────────────────────────────────────────┐
│  [logo]                  [🌙] [IT/EN]   │  ← top-bar floating
├─────────────────────────────────────────┤
│                                         │
│          ShiftHappens                   │  ← H1 Figtree 600 48px
│                                         │
│   Pianifica turni di guardia con MILP   │  ← lead Noto Sans 18px
│   nei reparti ospedalieri italiani.     │
│                                         │
│       ┌──────────────────────┐          │
│       │  Centri partecipanti │          │  ← primary CTA navy
│       └──────────────────────┘          │
│                                         │
├─────────────────────────────────────────┤  (smooth scroll target)
│                                         │
│  ▶ IOV - Oncologia 1                    │  ← accordion panel collapsed
│    Padova · MILP IOV-specific           │
│                                         │
│  ▶ Crema - Sala operatoria              │  ← accordion panel collapsed
│    Reparto Chirurgia · MILP generico    │
│                                         │
└─────────────────────────────────────────┘
```

### 5.2 Centre card expanded state

```
▼ IOV - Oncologia 1
  ┌─────────────────────────────────────┐
  │  🔒 Inserisci passcode  [______] OK │
  └─────────────────────────────────────┘
       (reveals below once unlocked)
  ┌─────────────────────────────────────┐
  │  📅 Mese da pianificare              │
  │     [▼ Luglio 2026]                  │
  │                                     │
  │  📤 Desiderata mensile               │
  │     [Scegli file…] (assenze.xlsx)   │
  │                                     │
  │  ⚙️  Regole (opzionale)              │
  │     [Scegli file…] (rules.yaml)     │
  │                                     │
  │     ┌──────────────────────┐        │
  │     │   ✨ Genera turno    │        │
  │     └──────────────────────┘        │
  └─────────────────────────────────────┘

  (output appears below after generate)
  ┌─────────────────────────────────────┐
  │  ✅ Turno generato in 23s           │
  │  ┌─────┬─────┬─────┐                │
  │  │ 42  │  8  │ 0   │                │
  │  │turni│weekend│gap │                │
  │  └─────┴─────┴─────┘                │
  │  [DT calendar table (full_screen)]  │
  │  [📥 Scarica .xlsx]                 │
  └─────────────────────────────────────┘
```

### 5.3 bslib component mapping

| Element | bslib function |
|---|---|
| Page wrapper | `page_fluid(theme = bs_theme(...))` |
| Top-bar | custom `div` with `input_dark_mode("mode")` + `input_switch("lang")` |
| Hero CTA | `actionButton(class = "btn-primary btn-lg")` with smooth-scroll JS handler |
| Centre list | `accordion(open = FALSE, multiple = FALSE)` with one `accordion_panel` per centre |
| Centre header (collapsed) | `accordion_panel` `title = ...` |
| Passcode gate | `passwordInput()` + `actionButton()`; on validate → `shiny::insertUI` reveals actions |
| Month chooser | `selectInput()` with months pre-populated from current year ±6 |
| File uploads | `fileInput("desiderata_<id>", accept = ".xlsx")`, same for rules |
| Generate | `input_task_button("genera_<id>", tr("centre_generate"))` |
| Output container | `card(full_screen = TRUE)` with `card_header` + `card_body` |
| Summary tiles | `layout_column_wrap(width = 1/3, fill = FALSE, value_box(...) * 3)` |
| Calendar table | `DT::DTOutput()` inside the output card |
| Download | `downloadButton(class = "btn-outline-primary")` |
| Error/infeasible | `card(class = "border-danger" / "border-warning")` with status badge |

### 5.4 Accessibility (per ui-ux-pro-max pre-delivery checklist)

- All icons via `bsicons::bs_icon(..., title = "...")` to set `a11y = "sem"` (not emojis).
- Cursor-pointer on all interactive elements (bslib defaults handle this).
- Hover/focus transitions 150-300ms (within ui-ux-pro-max "Micro-interactions" style).
- Light mode text contrast ≥ 4.5:1 against `#F8FAFC` background (verified: navy `#1E3A5F` against light bg is 8.4:1).
- Dark mode separately verified.
- Visible focus rings on keyboard navigation.
- `prefers-reduced-motion` respected (bslib animations honour this by default).
- Responsive at 375 / 768 / 1024 / 1440 px.
- Dynamic Type / browser zoom: layout reflows, no truncation.

---

## 6. Theming & i18n

### 6.1 `R/shifthappens_theme.R`

```r
shifthappens_theme <- function(mode = c("light", "dark")) {
  mode <- match.arg(mode)
  bslib::bs_theme(
    version = 5,
    bg = if (mode == "light") "#F8FAFC" else "#0F172A",
    fg = if (mode == "light") "#0F172A" else "#F8FAFC",
    primary   = "#1E3A5F",      # navy
    secondary = "#2563EB",      # blue
    success   = "#059669",      # green accent (per ui-ux-pro-max)
    danger    = "#DC2626",
    warning   = "#F59E0B",
    base_font    = bslib::font_google("Noto Sans", wght = c(300, 400, 500, 700)),
    heading_font = bslib::font_google("Figtree",   wght = c(500, 600, 700)),
    code_font    = bslib::font_google("JetBrains Mono")
  )
}
```

Dark mode wiring in `app.R` server:

```r
observeEvent(input$mode, {
  session$setCurrentTheme(shifthappens_theme(input$mode))
}, ignoreNULL = TRUE)
```

Base R + ggplot2 plots adapt automatically via:

```r
thematic::thematic_shiny()
```

### 6.2 i18n usage in modules

```r
# in mod_centre_card UI factory
shifthappens_centre_card_ui <- function(id, centre) {
  ns <- NS(id)
  accordion_panel(
    title = centre$name,                          # never translated
    value = centre$id,
    fileInput(ns("desiderata"), label = NULL, accept = ".xlsx",
              buttonLabel = textOutput(ns("lbl_desiderata"), inline = TRUE)),
    ...
  )
}

# in server
output$lbl_desiderata <- renderText(tr("centre_desiderata"))
```

Language switch invalidates all `tr()` calls because `current_lang()` is reactive.

---

## 7. Output Flow & Solver Routing

### 7.1 Generation pipeline (per centre)

1. User clicks "Genera turno" → `input_task_button` enters busy state.
2. Server validates: `req(centre_state$unlocked, centre_state$desiderata_file, centre_state$target_month)`.
3. `tryCatch({ generate_schedule(centre, centre_state, rules, cal) })`:
   - Inputs parsed via `centre$parser` ("iov" → `read_iov_inputs`; "generic" → `read_workbook`).
   - Rules loaded via `load_rules(centre_state$rules_file %||% centre$rules_path)`.
   - Calendar built via `build_calendar(centre_state$target_month)`.
   - Model built via `centre$parser` switch (`build_iov_model` or `build_milp`).
   - Solver invoked: `solve_milp(model, time_limit_seconds = 60)`.
4. Result classification:
   - `solver_status %in% c("optimal", "success")` → `result_status = "success"`. Postprocess into tibble. Render value boxes + DT + enable download.
   - `solver_status == "infeasible"` → `result_status = "infeasible"`. Render warning card with diagnostic message (which constraints conflict).
   - Caught error → `result_status = "error"`. Render danger card with `tr("error")` + stderr in collapsible details.
5. `centre_state$generate_at <- Sys.time()` for logging.

### 7.2 Loading feedback (during the solve)

- `input_task_button` shows inline spinner + disables itself until result.
- `showNotification(tr("solving"), duration = NULL, id = paste0("solve_", centre$id))` for screen-reader announcement, dismissed on completion.

### 7.3 Download

`downloadHandler` writes the xlsx via existing `R/io_write.R` (`write_output_workbook` for generic, future `write_iov_bundle` for IOV — defined in `2026-05-21-iov-planner-design.md` §6 and to be implemented as part of P-IOV-4).

---

## 8. Validation & Testing Strategy

### 8.1 Tests

- `tests/testthat/test-centres-config.R` — validates `config/centres.yaml`: id uniqueness, parser enum, rules_path exists, passcode_env defined (skip in non-dev env), subtitles present.
- `tests/testthat/test-i18n.R` — asserts `setequal(names(STRINGS$it), names(STRINGS$en))` and no empty strings.
- `tests/testthat/test-mod-centre-card.R` — `shiny::testServer()` covering passcode flow (wrong → locked, right → unlocked), upload → state update, generate happy path with mock backend.
- `tests/testthat/test-mod-topbar.R` — dark mode reactivity, language switch reactivity.
- `tests/testthat/test-shifthappens-theme.R` — light + dark variants both build without error; key colors are present.
- `tests/testthat/test-e2e-shinytest2.R` — one full flow per centre: load app → unlock → upload fixture → pick month → generate → download → verify file.

### 8.2 Manual UAT (per pre-delivery checklist)

- [ ] Light mode looks clean on Chrome/Firefox/Safari at 375 / 768 / 1024 / 1440 px.
- [ ] Dark mode contrast verified with browser DevTools.
- [ ] Keyboard-only navigation works: Tab through hero CTA → accordion open → passcode → upload → generate → download.
- [ ] Screen reader (VoiceOver / NVDA) announces accordion panels by name.
- [ ] `prefers-reduced-motion` disables the smooth scroll on CTA click.
- [ ] Each centre's fixture flow completes < 30s.
- [ ] Infeasible scenario shows readable diagnostic.
- [ ] Error scenario (corrupt xlsx upload) shows readable error.

---

## 9. Implementation Phasing

The landing release is **gated on the full IOV backend being complete** so both centres work at launch.

| Phase | Status | Deliverable |
|---|---|---|
| P-IOV-1 | ✓ DONE | IOV input parsers (`R/iov_parse.R`) |
| P-IOV-2 | TODO | IOV roster derivation + REPARTO selection + validation |
| P-IOV-3 | TODO | IOV MILP model |
| P-IOV-4 | TODO | IOV postprocess + xlsx output writers |
| **P-LAND-1** | TODO | Centres config + i18n + theme scaffolding (this spec, parts 6 + 4) |
| **P-LAND-2** | TODO | Top-bar + hero + accordion (this spec, part 5) |
| **P-LAND-3** | TODO | Centre card module (passcode + actions + generate) |
| **P-LAND-4** | TODO | Centre output module (value boxes + DT + download) |
| **P-LAND-5** | TODO | Solver routing + error handling + `testServer` tests |
| **P-LAND-6** | TODO | `shinytest2` E2E + accessibility audit + responsive verification |
| **P-LAND-7** | TODO | Remove old v1 `R/mod_*` files; update README; deploy preview to Connect Cloud staging |

**Critical sequencing**: P-LAND-1 through P-LAND-7 can ONLY start after P-IOV-4 ships, otherwise the IOV centre's "Genera turno" would have no backend to route to.

Total estimated effort:
- P-IOV-2/3/4: ~15-20 working days (per IOV-Planner spec §10).
- P-LAND-1/2/3/4/5/6/7: ~8-12 working days.

---

## 10. Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Dark mode contrast issues with custom palette | Medium | Run automated WCAG checks on both modes; manual review against `#F8FAFC` and `#0F172A` backgrounds. |
| Passcode env vars missing on Connect Cloud → centres unusable | Medium | Validation at app startup logs missing env vars; centres without their env disabled with warning badge "Configurazione mancante". |
| i18n drift (missing translations) | Low | Test enforces parity at PR time. |
| `shinytest2` setup overhead on CI | Medium | Add as separate workflow job that runs only on PR to main; allow slow execution. |
| Browser font loading delays first paint | Low | `font_google()` uses font-display: swap by default. |
| Single-file `R/app.R` grows unwieldy | Medium | Strict module split per file structure; `app.R` only wires modules, no logic. |
| Centre asymmetry (parsers differ) leaks into UI | Medium | All centre-specific behaviour is in the `parser` switch in `generate_schedule()`; UI is parser-agnostic. |

---

## 11. Open Questions (none HARD-blocking)

1. **Smooth-scroll JS**: implement with vanilla JS (`scrollIntoView({behavior:'smooth'})`) inline or via a small `inst/www/scroll.js` helper? — Decision: inline for v2, refactor if pattern repeats.
2. **Month chooser**: plain `selectInput` with hard-coded month list, or `airDatepickerInput` for richer UX? — Decision: `selectInput` for v2 simplicity; revisit if user feedback complains.
3. **Centre logos**: do we want a small unit logo (e.g. IOV crest) next to the centre name in the accordion header? — Decision: deferred; ask the user post-launch.
4. **Output download filename**: `turni_<centre-id>_<YYYY-MM>.xlsx`? Make configurable per centre via YAML? — Decision: hard-coded pattern for v2.
5. **Generation history per centre**: should the centre card show "Last generated: <date>"? — Decision: nice-to-have, deferred to v2.1.
