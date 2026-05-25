# Programmatic fixture builders for iov_parse tests.
# Helpers prefixed `.iov_fx_` so we never collide with src helpers.

.iov_fx_prospetto <- function(path) {
  wb <- openxlsx2::wb_workbook()$add_worksheet("LUGLIO-> SETTEMBRE")

  # Row 1: title block (cosmetic), Row 2: column headers.
  wb <- openxlsx2::wb_add_data(wb, sheet = 1, x = "PROSPETTO GUARDIE 2026 - LUGLIO",
                                dims = "A1", col_names = FALSE)
  headers <- data.frame(
    GIORNO = "GIORNO", DATA = "DATA",
    DIURNO = "GUARDIA 8:00-20:00", NOTTURNO = "GUARDIA 20:00-8:00",
    stringsAsFactors = FALSE
  )
  wb <- openxlsx2::wb_add_data(wb, sheet = 1, x = headers, dims = "A2",
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
  wb <- openxlsx2::wb_add_data(wb, sheet = 1, x = data, dims = "A3",
                                col_names = FALSE)
  openxlsx2::wb_save(wb, path, overwrite = TRUE)
  invisible(path)
}

.iov_fx_assenze <- function(path) {
  wb <- openxlsx2::wb_workbook()$add_worksheet("Foglio1")
  # Row 1: dow header; Row 2: day numbers; Row 3: "SPECIALISTI"; Rows 4-5: 2 attendings.
  wb <- openxlsx2::wb_add_data(wb, sheet = 1,
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
  wb <- openxlsx2::wb_workbook()$add_worksheet(sheet)

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
    wb <- openxlsx2::wb_add_data(wb, sheet = sheet, x = matrix(rows[[i]], nrow = 1),
                                 dims = paste0("A", i), col_names = FALSE)
  }

  # Year-color fills on row 3 (Rossi=1°viola, Bianchi=2°verde, Verdi=3°arancio, Neri=4°azzurro).
  wb <- openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "C3", color = openxlsx2::wb_color(hex = "FFB4A7D6"))
  wb <- openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "D3", color = openxlsx2::wb_color(hex = "FFD9EAD3"))
  wb <- openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "E3", color = openxlsx2::wb_color(hex = "FFF6B26B"))
  wb <- openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "F3", color = openxlsx2::wb_color(hex = "FF9FC5E8"))

  # Yellow "favorite" fill on 2 cells: row 6 col C (Rossi, Fri Jul 3) and row 9 col D (Bianchi, Sun Jul 5 GIORNO).
  wb <- openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "C6", color = openxlsx2::wb_color(hex = "FFFFFF00"))
  wb <- openxlsx2::wb_add_fill(wb, sheet = sheet, dims = "D9", color = openxlsx2::wb_color(hex = "FFFFFF00"))

  openxlsx2::wb_save(wb, path, overwrite = TRUE)
  invisible(path)
}

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
