#!/usr/bin/env Rscript
# One-off data update: bring IOV_MEMBERS.xlsx in sync with the July 2026
# active roster as defined in project memory.
#
# Changes applied:
#   1. Add "Jul" to active_months_2026 for the 17 ongoing ONCO 1 residents
#      who are part of the July 2026 active 21-resident roster.
#   2. Add 4 new rows for the 4 ex-ONCO 2 residents who joined the ONCO 1
#      pool in July 2026 (MASSA, BIVONA, BLOISE, BRAVI). First names left
#      empty pending verification by caposala.
#
# Roster source: project memory (project_iov_adaptation.md, July 2026 roster).
#
# Re-run: idempotent — re-applying the script on an already-updated file
# is a no-op (the substitutions match only the un-updated strings).

suppressPackageStartupMessages({
  library(openxlsx2)
  library(dplyr)
})

f <- "iov/analysis/IOV_MEMBERS.xlsx"
stopifnot(file.exists(f))

# Backup
backup <- sprintf("%s.bak-%s", f, format(Sys.Date(), "%Y%m%d"))
if (!file.exists(backup)) file.copy(f, backup)
cat("Backup ->", backup, "\n")

# Read current members sheet (preserve all columns + order)
wb <- wb_load(f)
members <- wb_to_df(wb, sheet = "members")

# Names of the 17 ongoing residents in July 2026 active roster (per memory)
july_active <- c(
  "ALAM", "BASOLI", "BERTIN", "BIONDI", "BOF", "BONELLO", "BOSA", "BOSIO",
  "DAL CENGIO", "DI MARCO", "DI PAOLO", "GAIANI", "LEOTTA", "PITTARELLO",
  "RONCHI", "SARUBBI", "SPEROTTO"
)
stopifnot(length(july_active) == 17L)

# 1) Add ";Jul" to active_months_2026 for these 17, if not already present
update_count <- 0L
for (name in july_active) {
  idx <- which(toupper(members$last_name) == name)
  if (length(idx) != 1L) {
    warning(sprintf("Expected exactly 1 row for %s, found %d — skipping",
                    name, length(idx)))
    next
  }
  current <- members$active_months_2026[idx]
  if (is.na(current) || !nzchar(current) || current == "-") {
    warning(sprintf("%s has empty active_months_2026 — skipping", name))
    next
  }
  if (grepl("\\bJul\\b", current)) {
    next  # already updated, idempotent
  }
  members$active_months_2026[idx] <- paste0(current, ";Jul")
  update_count <- update_count + 1L
}
cat("Updated active_months_2026 for", update_count, "ongoing residents\n")

# 2) Append 4 new rows for ex-ONCO 2 residents now in ONCO 1 (year 1° per memory).
#    First names left empty pending verification.
new_rows <- data.frame(
  last_name           = c("MASSA", "BIVONA", "BLOISE", "BRAVI"),
  first_name          = rep(NA_character_, 4L),
  role                = rep("Specializzando", 4L),
  unit                = rep("ONCO 1", 4L),
  primary_group       = rep(NA_character_, 4L),
  subgroup_secondary  = rep(NA_character_, 4L),
  in_guardie_rotation = rep("yes", 4L),
  reperibile_fasi_i   = rep("no", 4L),
  notes = paste("Joined ONCO 1 pool Jul 2026 from ONCO 2; year 1.",
                "First name to verify with caposala (added 2026-05-25)."),
  active_months_2026  = rep("Jul", 4L),
  stringsAsFactors    = FALSE
)
# Idempotency: skip names already present
new_rows <- new_rows[!(toupper(new_rows$last_name) %in%
                        toupper(members$last_name)), , drop = FALSE]
cat("Adding", nrow(new_rows), "new ex-ONCO 2 residents\n")

if (nrow(new_rows) > 0L) {
  members <- dplyr::bind_rows(members, new_rows)
}

# 3) Write the updated workbook (preserve other sheets unchanged)
wb_new <- wb_workbook()
wb_new$add_worksheet("members")
wb_new <- wb_add_data(wb_new, sheet = "members", x = members, col_names = TRUE)

# Preserve legend + tags sheets if present
for (other_sheet in setdiff(wb$get_sheet_names(), "members")) {
  df <- wb_to_df(wb, sheet = other_sheet)
  wb_new$add_worksheet(other_sheet)
  wb_new <- wb_add_data(wb_new, sheet = other_sheet, x = df, col_names = TRUE)
}

wb_save(wb_new, f, overwrite = TRUE)
cat("Wrote updated IOV_MEMBERS.xlsx (", nrow(members), "rows now)\n", sep = "")
