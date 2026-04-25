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
