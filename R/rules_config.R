#' Default values merged into any user-supplied rules YAML.
#' Internal — exposed only as a constant.
.rules_defaults <- list(
  unit = list(locale = "it"),
  limits = list(
    senior_max_per_month        = 7L,
    min_free_weekends_per_month = 2L,
    weekday_min_rest_days       = 1L,
    post_weekend_min_rest_days  = 1L,
    rolling_history_months      = 1L
  ),
  fairness_weights = list(
    monthly_total   = 100L,
    weekend_holiday = 50L,
    preference      = 20L,
    smoothness      = 5L
  ),
  solver = list(
    time_limit_seconds = 30L,
    fallback           = "highs"
  ),
  holidays_extra = list(),
  ui = list(
    primary_color  = "#1ca5b8",
    error_color    = "#c4302b",
    table_density  = "compact"
  )
)

#' Required top-level keys and required sub-keys per section.
.rules_required <- list(
  unit  = c("name"),
  roles = c("primary", "secondary")
)

#' Numeric keys whose values must be integer >= 0.
.rules_numeric <- list(
  limits = c("senior_max_per_month", "min_free_weekends_per_month",
             "weekday_min_rest_days", "post_weekend_min_rest_days",
             "rolling_history_months"),
  fairness_weights = c("monthly_total", "weekend_holiday",
                       "preference", "smoothness"),
  solver = c("time_limit_seconds")
)

#' Recursively merge two lists; right side wins.
#' Internal helper.
.merge_lists <- function(default, override) {
  if (!is.list(default) || !is.list(override)) return(override %||% default)
  for (k in names(override)) {
    default[[k]] <- if (is.list(default[[k]]) && is.list(override[[k]])) {
      .merge_lists(default[[k]], override[[k]])
    } else {
      override[[k]]
    }
  }
  default
}

`%||%` <- function(a, b) if (is.null(a)) b else a

#' Load and validate a rules YAML file.
#'
#' Required keys: unit.name, roles.primary, roles.secondary.
#' Optional keys are filled from .rules_defaults.
#' Numeric keys are coerced to integer and checked for non-negativity.
#'
#' @param path file path
#' @return validated, merged list
load_rules <- function(path) {
  if (!file.exists(path)) {
    stop("rules file not found: ", path)
  }
  raw <- yaml::read_yaml(path)
  if (!is.list(raw)) stop("rules file does not parse as a YAML mapping: ", path)

  # Check required keys
  for (section in names(.rules_required)) {
    for (key in .rules_required[[section]]) {
      if (is.null(raw[[section]][[key]])) {
        stop("missing required key ", section, ".", key)
      }
    }
  }

  merged <- .merge_lists(.rules_defaults, raw)

  # Validate numeric keys
  for (section in names(.rules_numeric)) {
    for (key in .rules_numeric[[section]]) {
      v <- merged[[section]][[key]]
      if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < 0) {
        stop("invalid value for ", section, ".", key,
             ": expected non-negative number, got ", deparse(v))
      }
      merged[[section]][[key]] <- as.integer(v)
    }
  }

  merged
}
