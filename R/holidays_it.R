#' Compute the date of Western Easter Sunday for a given year.
#'
#' Uses the Meeus / Jones / Butcher Gregorian algorithm. Valid for years
#' >= 1583. Returns a Date.
#'
#' @param year integer, e.g. 2026
#' @return Date object for Easter Sunday
easter_sunday <- function(year) {
  stopifnot(is.numeric(year), length(year) == 1, year >= 1583)
  a <- year %% 19
  b <- year %/% 100
  c <- year %% 100
  d <- b %/% 4
  e <- b %% 4
  f <- (b + 8) %/% 25
  g <- (b - f + 1) %/% 3
  h <- (19 * a + b - d - g + 15) %% 30
  i <- c %/% 4
  k <- c %% 4
  l <- (32 + 2 * e + 2 * i - h - k) %% 7
  m <- (a + 11 * h + 22 * l) %/% 451
  month <- (h + l - 7 * m + 114) %/% 31
  day <- ((h + l - 7 * m + 114) %% 31) + 1
  as.Date(sprintf("%04d-%02d-%02d", year, month, day))
}

#' Italian national holidays for a given year.
#'
#' Returns the 10 fixed-date national holidays plus Easter Sunday and
#' Easter Monday computed via easter_sunday().
#'
#' @param year integer
#' @return tibble with columns date (Date) and name (character)
italian_holidays <- function(year) {
  fixed <- tibble::tibble(
    name = c(
      "Capodanno", "Epifania", "Festa della Liberazione",
      "Festa dei Lavoratori", "Festa della Repubblica",
      "Ferragosto", "Tutti i Santi", "Immacolata Concezione",
      "Natale", "Santo Stefano"
    ),
    md = c(
      "01-01", "01-06", "04-25",
      "05-01", "06-02",
      "08-15", "11-01", "12-08",
      "12-25", "12-26"
    )
  )
  fixed$date <- as.Date(sprintf("%04d-%s", year, fixed$md))
  fixed$md <- NULL

  easter <- easter_sunday(year)
  movable <- tibble::tibble(
    date = c(easter, easter + 1L),
    name = c("Pasqua", "Pasquetta")
  )

  result <- dplyr::bind_rows(fixed, movable)
  result <- result[order(result$date), c("date", "name")]
  rownames(result) <- NULL
  tibble::as_tibble(result)
}

#' All holidays (national + per-unit extras) for a given year.
#'
#' @param year integer
#' @param holidays_extra list of named lists with `name` and `date` (MM-DD)
#' @return tibble with columns date (Date) and name (character)
holidays_for_year <- function(year, holidays_extra = NULL) {
  national <- italian_holidays(year)
  if (length(holidays_extra) == 0) return(national)

  extras <- purrr::map_dfr(holidays_extra, function(h) {
    tibble::tibble(
      name = h$name,
      date = as.Date(sprintf("%04d-%s", year, h$date))
    )
  })
  result <- dplyr::bind_rows(national, extras)
  result <- result[order(result$date), ]
  rownames(result) <- NULL
  tibble::as_tibble(result)
}
