# One-shot script: regenerates inst/examples/may2026_workbook.xlsx
# from the May 2026 data in docs/ShiftHappens_Vincoli.docx.
# Run with: Rscript inst/examples/build_may2026.R
suppressPackageStartupMessages({
  library(openxlsx2)
  library(tibble)
  library(dplyr)
  library(purrr)
})

operators <- tibble(
  surname = c("Briaschi", "Carniti", "Casella", "Fovanna", "Franzelli",
              "Mereu", "Vasile", "Confortini", "D'Aversa", "Diaco",
              "Ingiardi", "Leka", "Notaroberto", "Novasconi", "Ricetti"),
  name = c("Martina", "Monica", "Letizia", "Valentina", "Claudia",
           "Tiziana", "Rocco", "Diego", "", "Maria",
           "", "Rachela", "", "", ""),
  role = c("senior", "senior", "senior", "senior", "senior",
           "senior", "senior", "nurse_2", "oss_2", "nurse_2",
           "oss_2", "nurse_2", "oss_2", "oss_2", "oss_2"),
  part_time_pct = c(100, 100, 100, 75, 100,
                    100, 100, 100, 100, 100,
                    100, 100, 100, 100, 100),
  active_from = as.Date("2024-01-01"),
  active_to   = as.Date("9999-12-31")
)

may <- tibble(
  date = as.Date("2026-05-01") + 0:30,
  primary_day = c(
    "Fovanna","Franzelli","Fovanna","Carniti","Casella",
    "Franzelli","Vasile","Mereu","Franzelli","Franzelli",
    "Fovanna","Vasile","Mereu","Carniti","Franzelli",
    "Casella","Fovanna","Vasile","Casella","Mereu",
    "Franzelli","Briaschi","Fovanna","Mereu","Carniti",
    "Briaschi","Casella","Mereu","Briaschi","Vasile","Vasile"
  ),
  primary_night = c(
    "Mereu","Casella","Briaschi",NA,NA,
    NA,NA,NA,"Carniti","Casella",
    NA,NA,NA,NA,NA,
    "Briaschi","Briaschi",NA,NA,NA,
    NA,NA,"Vasile","Vasile",NA,
    NA,NA,NA,NA,"Carniti","Carniti"
  ),
  second_day = c(
    "Notaroberto","Diaco","Leka","Ingiardi","Notaroberto",
    "Leka","Ricetti","Novasconi","Diaco","D'Aversa",
    "Confortini","Diaco","Novasconi","Notaroberto","D'Aversa",
    "Confortini","Confortini","Ingiardi","Novasconi","Leka",
    "Diaco","Confortini","Ricetti","Leka","Diaco",
    "Notaroberto","Confortini","Leka","Ricetti","Ingiardi","Novasconi"
  ),
  second_night = c(
    "Leka","Notaroberto","D'Aversa",NA,NA,
    NA,NA,NA,"Ricetti","Novasconi",
    NA,NA,NA,NA,NA,
    "Diaco","Ricetti",NA,NA,NA,
    NA,NA,"D'Aversa","Novasconi",NA,
    NA,NA,NA,NA,"Confortini","Ingiardi"
  )
)

# Build history with one row per non-NA cell.
# May 2026 holidays: 2026-05-01 (Festa dei Lavoratori, Friday)
holiday_dates <- as.Date(c("2026-05-01"))

history <- pmap_dfr(may, function(date, primary_day, primary_night, second_day, second_night) {
  rows <- list()
  wday <- as.integer(format(date, "%u"))
  is_weekend <- wday %in% c(6L, 7L)
  is_holiday <- date %in% holiday_dates

  if (is_weekend || is_holiday) {
    day_kind   <- ifelse(is_holiday, "holiday_day",   "weekend_day")
    night_kind <- ifelse(is_holiday, "holiday_night", "weekend_night")
    if (!is.na(primary_day))   rows[[length(rows) + 1]] <- list(date = date, slot = day_kind,   role_slot = "first",  operator_id = primary_day)
    if (!is.na(primary_night)) rows[[length(rows) + 1]] <- list(date = date, slot = night_kind, role_slot = "first",  operator_id = primary_night)
    if (!is.na(second_day))    rows[[length(rows) + 1]] <- list(date = date, slot = day_kind,   role_slot = "second", operator_id = second_day)
    if (!is.na(second_night))  rows[[length(rows) + 1]] <- list(date = date, slot = night_kind, role_slot = "second", operator_id = second_night)
  } else {
    if (!is.na(primary_day))   rows[[length(rows) + 1]] <- list(date = date, slot = "weekday_night", role_slot = "first",  operator_id = primary_day)
    if (!is.na(second_day))    rows[[length(rows) + 1]] <- list(date = date, slot = "weekday_night", role_slot = "second", operator_id = second_day)
  }
  bind_rows(rows)
})

absences <- tibble(
  operator_id = character(),
  date_from   = as.Date(character()),
  date_to     = as.Date(character()),
  type        = character()
)

preferences <- tibble(
  operator_id = c("Fovanna", "Fovanna", "Fovanna"),
  weekday     = c(4L, 5L, 6L),       # Thu, Fri, Sat
  slot_type   = c(NA_character_, NA_character_, "day"),
  polarity    = c("avoid", "avoid", "avoid"),
  hard        = c(FALSE, FALSE, FALSE)
)

month <- tibble(month = "2026-06")

wb <- wb_workbook()
wb$add_worksheet("operators")$add_data(x = operators)
wb$add_worksheet("history")$add_data(x = history)
wb$add_worksheet("absences")$add_data(x = absences)
wb$add_worksheet("preferences")$add_data(x = preferences)
wb$add_worksheet("month")$add_data(x = month)

out_path <- "inst/examples/may2026_workbook.xlsx"
wb_save(wb, out_path)
message("Wrote ", out_path)
