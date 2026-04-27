test_that("write_output_workbook round-trips schedule + summary", {
  schedule <- tibble::tibble(
    date = as.Date(c("2026-06-01","2026-06-06","2026-06-07")),
    weekday = c("L","S","D"),
    `1° reperibile` = c("S1", "S1 / S2", "S2 / S3"),
    `2° reperibile` = c("J1", "J1 / J2", "J2 / J3")
  )
  summary_df <- tibble::tibble(
    operator_id = c("S1","S2","J1"),
    role = c("senior","senior","nurse_2"),
    n_first = c(1L,1L,0L),
    n_second = c(0L,0L,1L),
    n_weekend = c(1L,2L,1L),
    n_holiday = c(0L,0L,0L),
    total = c(1L,1L,1L),
    carry_in_window = c(0L,0L,0L),
    delta_vs_mean = c(0,0,0)
  )
  diagnostics <- tibble::tibble(
    field = c("solver_status","runtime_seconds","objective_value"),
    value = c("optimal","0.42","17.0")
  )
  out_path <- tempfile(fileext = ".xlsx")
  write_output_workbook(out_path, schedule, summary_df, diagnostics)
  expect_true(file.exists(out_path))

  sheets <- readxl::excel_sheets(out_path)
  expect_setequal(sheets, c("schedule","summary","diagnostics"))

  rt_schedule <- readxl::read_excel(out_path, sheet = "schedule")
  expect_equal(nrow(rt_schedule), 3L)
  expect_equal(rt_schedule$weekday, c("L","S","D"))

  rt_summary <- readxl::read_excel(out_path, sheet = "summary")
  expect_equal(nrow(rt_summary), 3L)
  expect_equal(sort(rt_summary$operator_id), c("J1","S1","S2"))

  rt_diag <- readxl::read_excel(out_path, sheet = "diagnostics")
  expect_equal(nrow(rt_diag), 3L)

  unlink(out_path)
})

test_that("write_output_workbook handles NULL schedule (infeasible) gracefully", {
  out_path <- tempfile(fileext = ".xlsx")
  diagnostics <- tibble::tibble(
    field = c("solver_status", "infeasibility_diagnosis"),
    value = c("infeasible", "[senior_cap] Raise senior_max_per_month.")
  )
  write_output_workbook(out_path, schedule = NULL, summary = NULL,
                        diagnostics = diagnostics)
  expect_true(file.exists(out_path))
  sheets <- readxl::excel_sheets(out_path)
  expect_true("diagnostics" %in% sheets)
  rt_diag <- readxl::read_excel(out_path, sheet = "diagnostics")
  expect_equal(nrow(rt_diag), 2L)
  unlink(out_path)
})
