# ShiftHappens

Web app to rapidly and efficiently organize on-call shifts for a healthcare team within a hospital unit. Built in R + Shiny, deployed on Posit Connect Cloud, stateless Excel-in / Excel-out.

The app generates a monthly on-call schedule via mixed-integer linear programming (MILP), respecting all hard rules from a per-unit YAML configuration and minimizing fairness deviations across operators.

## Architecture

See `docs/superpowers/specs/2026-04-25-shifthappens-design.md` for the full design specification (~726 lines, 15 sections).

Pipeline:

```
Excel upload → read_workbook → validate_inputs → build_calendar
            → build_model_context → build_milp → solve_milp
            → postprocess_solution → write_output_workbook → Excel download
```

## Local development

```bash
# Restore packages
Rscript -e 'renv::restore()'

# Run tests
Rscript -e 'pkgload::load_all("."); testthat::test_local()'

# Launch the app
Rscript -e 'shiny::runApp(launch.browser = TRUE)'
```

## Per-unit deployment to Posit Connect Cloud

For each new hospital unit:

1. Copy `config/rules.yaml` → `config/rules-<unit>.yaml`. Edit `unit.name`, `holidays_extra`, and any rule overrides (senior cap, free-weekend min, fairness weights).
2. Publish a new app instance to Connect Cloud pointing at this Git repo.
3. In the Connect Cloud app's Settings → Environment, set:
   - `RULES_CONFIG_PATH` = `config/rules-<unit>.yaml`
   - `APP_PASSCODE` = the unit's shared passcode (any non-empty string; users must enter it on the gate screen)
4. Share the URL + passcode with the unit's caposala.

Same Git repo, multiple Connect Cloud deployments, zero per-unit code branching.

## Input workbook format

Five sheets uploaded by the user (single `.xlsx` file):

- **`operators`** — surname, name, role (`senior` / `nurse_2` / `oss_2`), part_time_pct, active_from, active_to.
- **`history`** — past assignments (date, slot, role_slot, operator_id) used for the rolling 1-month rebalance.
- **`absences`** — operator_id, date_from, date_to, type (`L104` / `CSR` / `study` / `vacation` / `sick` / `other`).
- **`preferences`** — operator_id, weekday (1-7 or blank), slot_type (`day` / `night` / blank), polarity (`avoid` / `prefer`), hard (TRUE/FALSE).
- **`month`** — single cell with target year-month in `YYYY-MM` format.

See spec §5.1 for column-by-column schemas. Example: `inst/examples/may2026_workbook.xlsx`.

## Output workbook format

Three sheets returned to the user:

- **`schedule`** — calendar layout: date, weekday letter (L/M/M/G/V/S/D), 1° reperibile, 2° reperibile. Weekend and holiday rows shaded `#f7f7f7`.
- **`summary`** — per-operator counts: n_first, n_second, n_weekend, n_holiday, total, carry_in_window, delta_vs_mean.
- **`diagnostics`** — solver status, runtime, objective value, infeasibility diagnosis (when relevant).

## YAML rules configuration

`config/rules.yaml` is the per-unit knob file. Key sections:

- `unit.name` — display name in the header
- `roles.primary` / `roles.secondary` — which operator roles can take 1° / 2°
- `limits.*` — senior_max_per_month, min_free_weekends_per_month, weekday_min_rest_days, post_weekend_min_rest_days, rolling_history_months
- `fairness_weights.*` — relative weights of the four soft objective tiers (monthly_total, weekend_holiday, preference, smoothness)
- `solver.time_limit_seconds` — solver time budget (default 30s)
- `holidays_extra` — per-unit local holidays (e.g., patron saint feasts) as `[{name: "...", date: "MM-DD"}]`
- `ui.primary_color` — accent color for the unit (curbcut.ca-inspired teal `#1ca5b8` by default)

See spec §6 for the full schema.

## Testing

The R suite covers parsing, validation, calendar/holiday logic, MILP build (10 hard constraints + 3 soft tiers), solver outcomes, and round-trip Excel I/O. Total: 189 passing assertions, 1 skipped (timeout branch — solver-speed dependent).

```bash
Rscript -e 'pkgload::load_all("."); testthat::test_local()'
```

CI (GitHub Actions) runs `R CMD check` + `testthat::test_local()` on Ubuntu 22.04 to match Connect Cloud's runtime.

## Deferred to v1.1

- Cell-locking with re-optimization (MILP supports it; UI not yet built).
- Smoothness tier (Tier 4) of the soft objective — needs linearization.
- §9.2 non-blocking validation warnings (4 rules deferred).
- `relaxed_soft_preferences` diagnostics row.
- `shinytest2` end-to-end tests.
- English UI via `i18n_en.R`.

See `docs/superpowers/plans/2026-04-25-shifthappens.md` (Tasks 5.2, 6.7, 8.2) and the spec §14 v1.1 backlog for the full list.
