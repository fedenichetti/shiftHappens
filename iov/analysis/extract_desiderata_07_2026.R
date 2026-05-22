#!/usr/bin/env Rscript
# Extract July 2026 resident desiderata from
# `Turni coguardia + guardia 2026 specializzandi.xlsx` into a normalized
# long-format workbook with explicit `year`, `preference`, and `status` columns.
#
# Source legend (user-confirmed 2026-05-21):
#   X / x  -> unavailable_soft (prefers no shift, but assignable if needed)
#   AF/af  -> unavailable_hard (ferie)
#   AC/ac  -> unavailable_hard (assenza congresso)
#   yellow fill (FFFFFF00 / FFFFF2CC) -> preference = favorite
#   row 3 cell fill color per resident encodes year:
#     red FFFF0000 / dark red FF980000 / coral FFE06666 / pink-red FFF4CCCC
#       -> not_in_rotation (ex-residents, no longer available)
#     pink FFEAD1DC                              -> 5
#     light blue FF9FC5E8 / FFCFE2F3 / FFC9DAF8  -> 4
#     orange FFF6B26B / FFF9CB9C / FFFCE5CD      -> 3
#     green FF93C47D / FFB6D7A8 / FFD9EAD3       -> 2
#     purple FFB4A7D6 / FFD9D2E9                 -> 1

suppressPackageStartupMessages({
  library(openxlsx2)
  library(dplyr)
  library(tidyr)
  library(stringr)
})

f_in  <- "iov/Turni coguardia + guardia 2026 specializzandi.xlsx"
f_out <- "iov/analysis/desiderata_07_2026.xlsx"

wb <- wb_load(f_in)
sh <- which(wb$get_sheet_names() == "Luglio 2026")

# ---- Build style -> fill rgb lookup ----------------------------------------
cellXfs <- wb$styles_mgr$styles$cellXfs            # 1-indexed vector of xf XML
fills   <- wb$styles_mgr$styles$fills              # 1-indexed vector of fill XML

xf_to_fill_id <- function(xf_xml) {
  m <- regmatches(xf_xml, regexpr('fillId="([0-9]+)"', xf_xml))
  if (length(m) == 0) NA_integer_ else as.integer(sub('fillId="', "", sub('"$', "", m)))
}
fill_to_rgb <- function(fill_xml) {
  m <- regmatches(fill_xml, regexpr('fgColor rgb="([A-F0-9]+)"', fill_xml))
  if (length(m) == 0) NA_character_ else sub('"$', "", sub('fgColor rgb="', "", m))
}

xf_fillId <- vapply(cellXfs, xf_to_fill_id, integer(1))
fill_rgb  <- vapply(fills,   fill_to_rgb,    character(1))

style_to_rgb <- function(style_idx) {
  # cell c_s is 0-based; cellXfs is 1-based R vector
  if (is.na(style_idx) || style_idx == "" ) return(NA_character_)
  i <- as.integer(style_idx) + 1L
  if (i < 1L || i > length(xf_fillId)) return(NA_character_)
  fid <- xf_fillId[i]
  if (is.na(fid)) return(NA_character_)
  fill_rgb[fid + 1L]
}

# ---- Read cells ------------------------------------------------------------
cc <- wb$worksheets[[sh]]$sheet_data$cc

# Shared strings table (0-indexed): XML strings like "<si><t>Bonomi</t></si>"
ss_xml <- wb$sharedStrings
extract_si_text <- function(x) {
  if (is.na(x) || x == "") return(NA_character_)
  m <- regmatches(x, gregexpr("<t[^>]*>[^<]*</t>", x))[[1]]
  if (length(m) == 0) return("")
  texts <- vapply(m, function(t) sub("</t>$", "", sub("^<t[^>]*>", "", t)), character(1))
  paste(texts, collapse = "")
}
ss <- vapply(ss_xml, extract_si_text, character(1))

# Handle multi-letter columns (AA, AB, ...): convert col letters to numeric
col_letter_to_num <- function(x) {
  vapply(x, function(s) {
    if (is.na(s) || s == "") return(NA_integer_)
    chars <- strsplit(s, "")[[1]]
    nums  <- match(chars, LETTERS)
    Reduce(function(a, b) a * 26L + b, nums)
  }, integer(1))
}
cc$col <- col_letter_to_num(sub("[0-9]+$", "", cc$c_r))
cc$row <- as.integer(cc$row_r)

# Inline string handling: when c_t == "inlineStr" the value is in `is`
get_value <- function(row) {
  if (!is.na(row$c_t) && row$c_t == "inlineStr") {
    m <- regmatches(row$is, regexpr("<t[^>]*>([^<]*)</t>", row$is))
    if (length(m)) sub("</t>$", "", sub("^<t[^>]*>", "", m)) else NA_character_
  } else {
    if (is.na(row$v) || row$v == "") NA_character_ else row$v
  }
}

# Easier: build a tibble with value + fill rgb
cells <- tibble(
  row   = cc$row,
  col   = cc$col,
  cs    = cc$c_s,
  c_t   = cc$c_t,
  v     = cc$v,
  is    = cc$is
) |>
  rowwise() |>
  mutate(value = {
    if (!is.na(c_t) && c_t == "s") {
      # shared string: v is the 0-indexed SST index
      idx <- suppressWarnings(as.integer(v))
      if (is.na(idx) || idx + 1L > length(ss)) NA_character_ else ss[idx + 1L]
    } else if (!is.na(c_t) && c_t == "inlineStr") {
      m <- regmatches(is, regexpr("<t[^>]*>([^<]*)</t>", is))
      if (length(m)) sub("</t>$", "", sub("^<t[^>]*>", "", m)) else NA_character_
    } else if (!is.na(v) && v != "") v else NA_character_
  },
  fill_rgb = style_to_rgb(cs)) |>
  ungroup() |>
  select(row, col, value, fill_rgb)

# ---- Identify residents (row 3) -------------------------------------------
year_map <- c(
  # True reds → ex-residents (no longer in rotation)
  "FFFF0000" = "0", "FF980000" = "0", "FFE06666" = "0",
  # Pinks → 5° anno (rosa)
  "FFF4CCCC" = "5", "FFEAD1DC" = "5",
  # Blues → 4° anno (azzurro)
  "FF9FC5E8" = "4", "FFCFE2F3" = "4", "FFC9DAF8" = "4", "FFA4C2F4" = "4",
  # Oranges → 3° anno (arancio)
  "FFF6B26B" = "3", "FFF9CB9C" = "3", "FFFCE5CD" = "3",
  # Greens → 2° anno (verde)
  "FF93C47D" = "2", "FFB6D7A8" = "2", "FFD9EAD3" = "2",
  # Purples → 1° anno (viola)
  "FFB4A7D6" = "1", "FFD9D2E9" = "1"
)
year_for_rgb <- function(rgb) {
  out <- unname(year_map[rgb])
  ifelse(is.na(out), "unknown", out)
}

residents <- cells |>
  filter(row == 3, !is.na(value)) |>
  mutate(year_raw = year_for_rgb(fill_rgb)) |>
  select(col, resident = value, fill_rgb_resident = fill_rgb, year_raw)

# Some resident cells may not have an explicit fill (year = unknown).
# Cross-check: if it's row 3 and below it has data, keep it.

# ---- Build day/date index from cols A, B ----------------------------------
day_idx <- cells |>
  filter(col %in% 1:2, row >= 4) |>
  select(row, col, value) |>
  pivot_wider(names_from = col, values_from = value, names_prefix = "c") |>
  rename(dow = c1, day = c2) |>
  mutate(day  = suppressWarnings(as.integer(day)),
         date = as.Date(sprintf("2026-07-%02d", day)))

# Weekend days (Sab/Dom) appear twice. Convention: 1st row = GIORNO, 2nd = NOTTE.
# Weekday rows = single, NOTTE only (per IOV_RULES.md).
day_idx <- day_idx |>
  filter(!is.na(day)) |>
  arrange(row) |>
  group_by(date) |>
  mutate(
    is_weekend = dow %in% c("Sab", "Dom"),
    seq        = row_number(),
    shift      = case_when(
      is_weekend & seq == 1 ~ "GIORNO",
      is_weekend & seq == 2 ~ "NOTTE",
      TRUE                  ~ "NOTTE"
    )
  ) |>
  ungroup() |>
  select(row, dow, date, shift)

# ---- Build long-format desiderata -----------------------------------------
yellow_rgbs <- c("FFFFFF00", "FFFFF2CC", "FFFFE599", "FFFFD966")

parse_status <- function(v) {
  if (is.na(v) || str_trim(v) == "") return("available")
  vt <- toupper(str_trim(v))
  if (vt %in% c("X")) return("unavailable_soft")
  if (str_starts(vt, "AF")) return("ferie")     # handles "AF", "AF pomeriggio", "AF)"
  if (str_starts(vt, "AC")) return("congresso")
  "other"  # unknown / annotation
}

dat <- cells |>
  filter(row >= 4, col >= 3) |>
  inner_join(residents |> select(col, resident, year_raw), by = "col") |>
  inner_join(day_idx, by = "row") |>
  rowwise() |>
  mutate(
    status     = parse_status(value),
    preference = if (!is.na(fill_rgb) && fill_rgb %in% yellow_rgbs) "favorite" else "neutral",
    raw_value  = value
  ) |>
  ungroup() |>
  select(date, dow, shift, resident, year = year_raw, status, preference, raw_value, fill_rgb)

# Drop blank-named columns and the 2 trailing "Assegnazione …BOZZA" template
# columns which are NOT residents.
dat_clean <- dat |>
  filter(!is.na(resident), str_trim(resident) != "") |>
  filter(!str_detect(resident, regex("Assegnazione", ignore_case = TRUE)))
residents <- residents |>
  filter(!str_detect(resident, regex("Assegnazione", ignore_case = TRUE)))

# ---- Diagnostics ----------------------------------------------------------
cat("Residents detected:\n")
print(residents |> count(year_raw))
cat("\nStatus distribution:\n")
print(dat_clean |> count(status))
cat("\nPreference distribution:\n")
print(dat_clean |> count(preference))
cat("\nDates parsed:\n")
print(range(dat_clean$date, na.rm = TRUE))
cat("\nResident roster (with detected year):\n")
print(residents |> arrange(col), n = 100)

# ---- Write derived workbook -----------------------------------------------
wb_out <- wb_workbook()
wb_out$add_worksheet("desiderata_long")
wb_out$add_data(sheet = "desiderata_long", x = dat_clean)
wb_out$add_worksheet("residents")
wb_out$add_data(sheet = "residents", x = residents |> arrange(col))
wb_out$add_worksheet("legend")
legend <- tibble(
  field = c("status: available", "status: unavailable_soft", "status: ferie",
            "status: congresso", "preference: favorite", "preference: neutral",
            "year: 1-5", "year: 0", "year: unknown",
            "shift: GIORNO (weekend only)", "shift: NOTTE"),
  meaning = c("blank cell, person fully available",
              "X / x — prefers not, but assignable",
              "AF — ferie, hard unavailable",
              "AC — congresso, hard unavailable",
              "yellow-filled cell — person likes this date",
              "no fill — neutral",
              "1°…5° anno specializzazione (color-derived)",
              "ex-resident, no longer in rotation (red fills)",
              "no recognizable color — verify manually",
              "Saturday/Sunday/holiday 08:00-20:00",
              "every day 20:00-08:00")
)
wb_out$add_data(sheet = "legend", x = legend)
wb_save(wb_out, f_out, overwrite = TRUE)
cat("\nWrote:", f_out, "\n")
