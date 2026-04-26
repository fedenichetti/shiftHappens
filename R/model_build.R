#' Build the deterministic context the MILP needs:
#'   - operators: tibble with op_idx (1..N), operator_id, role
#'   - calendar:  tibble with day_idx (1..D), date, slot_kind, ... slots
#'   - rules:     pass-through rules list
#'   - absent_idx: matrix of (op_idx, day_idx) pairs the operator can't cover
#'   - carry_in:  per-operator counts from history within rolling window
#'
#' This is plain data transformation -- no ompr involvement yet.
#'
#' @param wb result of read_workbook
#' @param rules result of load_rules
#' @param cal  result of build_calendar (for the target month)
#' @return list
build_model_context <- function(wb, rules, cal) {
  ops <- wb$operators
  ops$operator_id <- ifelse(
    is.na(ops$name) | ops$name == "",
    ops$surname,
    paste(ops$surname, ops$name, sep = "_")
  )
  # collapse duplicates after id construction
  ops <- dplyr::distinct(ops, operator_id, .keep_all = TRUE)
  ops$op_idx <- seq_len(nrow(ops))

  cal$day_idx <- seq_len(nrow(cal))

  # Absence (op_idx, day_idx) pairs
  absent <- matrix(integer(0), ncol = 2)
  if (!is.null(wb$absences) && nrow(wb$absences) > 0) {
    for (i in seq_len(nrow(wb$absences))) {
      a <- wb$absences[i, ]
      op_match <- ops$op_idx[ops$operator_id == a$operator_id |
                               ops$surname == a$operator_id]
      if (length(op_match) == 0) next
      days <- seq(a$date_from, a$date_to, by = "day")
      day_match <- cal$day_idx[cal$date %in% days]
      if (length(day_match) == 0) next
      pairs <- expand.grid(op = op_match, day = day_match)
      absent <- rbind(absent, as.matrix(pairs))
    }
  }

  # carry_in counts from history in rolling window
  win_months <- rules$limits$rolling_history_months
  target_start <- as.Date(sprintf(
    "%04d-%02d-01",
    lubridate::year(cal$date[1]),
    lubridate::month(cal$date[1])
  ))
  win_start <- target_start - months(win_months)
  hist <- if (!is.null(wb$history) && nrow(wb$history) > 0) {
    wb$history[wb$history$date >= win_start &
                 wb$history$date < target_start, ]
  } else {
    wb$history
  }
  carry <- if (!is.null(hist) && nrow(hist) > 0) {
    dplyr::count(hist, operator_id, name = "carry_count")
  } else {
    tibble::tibble(operator_id = character(0), carry_count = integer(0))
  }
  carry_full <- ops |>
    dplyr::select("op_idx", "operator_id") |>
    dplyr::left_join(carry, by = "operator_id") |>
    dplyr::mutate(carry_count = tidyr::replace_na(.data$carry_count, 0L))

  list(
    operators   = ops,
    calendar    = cal,
    rules       = rules,
    absent_idx  = absent,
    carry_in    = carry_full,
    preferences = wb$preferences
  )
}

#' Build the MILP for an on-call month using the prepared context.
#'
#' Decision variable: x[op, day, slot, role_pos] in {0,1} where slot is
#' the index within calendar$slots[[day]] and role_pos in {1,2} for
#' (first, second).
#'
#' This task adds H1 (coverage) only. Subsequent tasks layer on H2-H10.
#'
#' @param ctx result of build_model_context
#' @return ompr optimization_model
build_milp <- function(ctx) {
  N_op  <- nrow(ctx$operators)
  N_day <- nrow(ctx$calendar)
  # Maximum slots-per-day across the month (for tensor sizing).
  max_slots <- max(purrr::map_int(ctx$calendar$slots, nrow))
  # Build a tibble of valid (day_idx, slot_idx, role) triples.
  slot_grid <- purrr::map_dfr(seq_len(N_day), function(d) {
    s <- ctx$calendar$slots[[d]]
    s$day_idx  <- d
    s$slot_idx <- seq_len(nrow(s))
    s
  })

  m <- ompr::MIPModel()
  m <- ompr::add_variable(
    m,
    x[op, day, slot, role_pos],
    op       = 1:N_op,
    day      = 1:N_day,
    slot     = 1:max_slots,
    role_pos = 1:2,
    type     = "binary"
  )

  # H1 coverage: for every (day, slot, role_pos) tuple that exists in
  # slot_grid, exactly one operator is assigned. role_pos 1 = "first",
  # 2 = "second"; map slot_grid$role to role_pos here.
  for (i in seq_len(nrow(slot_grid))) {
    d  <- slot_grid$day_idx[i]
    s  <- slot_grid$slot_idx[i]
    rp <- if (slot_grid$role[i] == "first") 1L else 2L
    m <- ompr::add_constraint(m, ompr::sum_over(x[op, d, s, rp], op = 1:N_op) == 1)
  }

  # Hidden tuples (slot_idx beyond what this day actually has): force to 0.
  for (d in seq_len(N_day)) {
    actual_slots <- nrow(ctx$calendar$slots[[d]])
    if (actual_slots < max_slots) {
      for (s in (actual_slots + 1L):max_slots) {
        for (rp in 1:2) {
          m <- ompr::add_constraint(m, ompr::sum_over(x[op, d, s, rp], op = 1:N_op) == 0)
        }
      }
    }
  }

  # H2: only seniors take role_pos = 1 (first)
  senior_idx <- ctx$operators$op_idx[ctx$operators$role == "senior"]
  junior_idx <- setdiff(seq_len(N_op), senior_idx)
  for (op_j in junior_idx) {
    m <- ompr::add_constraint(m,
      ompr::sum_over(x[op_j, d, s, 1], d = 1:N_day, s = 1:max_slots) == 0
    )
  }
  # H3: any operator may take role_pos = 2 -- no extra constraint needed,
  # variables already exist for all ops.

  # H4: absent (op, day) pairs are zeroed across all slots/roles.
  if (nrow(ctx$absent_idx) > 0) {
    for (i in seq_len(nrow(ctx$absent_idx))) {
      op_a  <- ctx$absent_idx[i, 1]
      day_a <- ctx$absent_idx[i, 2]
      m <- ompr::add_constraint(m,
        ompr::sum_over(x[op_a, day_a, s, rp], s = 1:max_slots, rp = 1:2) == 0
      )
    }
  }

  # H5: weekday rest. For each operator and each consecutive (day d, d+1)
  # both being weekdays: sum of all assignments on d + sum on d+1 <= 1.
  if (N_day >= 2) {
    for (op_i in 1:N_op) {
      for (d in 1:(N_day - 1)) {
        both_weekday <- (ctx$calendar$slot_kind[d] == "weekday") &&
                        (ctx$calendar$slot_kind[d + 1] == "weekday")
        if (!both_weekday) next
        d_next <- d + 1L
        m <- ompr::add_constraint(m,
          ompr::sum_over(x[op_i, d, s, rp], s = 1:max_slots, rp = 1:2) +
          ompr::sum_over(x[op_i, d_next, s, rp], s = 1:max_slots, rp = 1:2) <= 1
        )
      }
    }
  }

  # H6: post-weekend rest. If day d is weekend/holiday and d+1 is weekday,
  # the operator can't do both.
  if (N_day >= 2) {
    for (op_i in 1:N_op) {
      for (d in 1:(N_day - 1)) {
        d_we <- ctx$calendar$slot_kind[d] %in% c("weekend", "holiday")
        next_wd <- ctx$calendar$slot_kind[d + 1] == "weekday"
        if (!(d_we && next_wd)) next
        d_next <- d + 1L
        m <- ompr::add_constraint(m,
          ompr::sum_over(x[op_i, d, s, rp], s = 1:max_slots, rp = 1:2) +
          ompr::sum_over(x[op_i, d_next, s, rp], s = 1:max_slots, rp = 1:2) <= 1
        )
      }
    }
  }

  # H7: no 24h consecutive on weekend/holiday days. Forbid:
  #   (day=d, period=day) AND (day=d, period=night)            -- same day
  #   (day=d, period=night) AND (day=d+1, period=day)          -- night-then-day
  for (op_i in 1:N_op) {
    for (d in 1:N_day) {
      if (ctx$calendar$slot_kind[d] == "weekday") next
      slots_today <- ctx$calendar$slots[[d]]
      day_slots   <- which(slots_today$period == "day")
      night_slots <- which(slots_today$period == "night")
      if (length(day_slots) > 0 && length(night_slots) > 0) {
        m <- ompr::add_constraint(m,
          ompr::sum_over(x[op_i, d, s, rp], s = day_slots, rp = 1:2) +
          ompr::sum_over(x[op_i, d, s, rp], s = night_slots, rp = 1:2) <= 1
        )
      }
      # cross-day: night of d + day of d+1 (if d+1 also non-weekday)
      if (d < N_day && ctx$calendar$slot_kind[d + 1] != "weekday") {
        d_next <- d + 1L
        slots_next <- ctx$calendar$slots[[d_next]]
        next_day_slots <- which(slots_next$period == "day")
        if (length(night_slots) > 0 && length(next_day_slots) > 0) {
          m <- ompr::add_constraint(m,
            ompr::sum_over(x[op_i, d, s, rp], s = night_slots, rp = 1:2) +
            ompr::sum_over(x[op_i, d_next, s, rp], s = next_day_slots, rp = 1:2) <= 1
          )
        }
      }
    }
  }

  # H8: each operator works at most (total_weekends - min_free) weekends.
  # A weekend is identified by ISO week (so Sat + Sun group together).
  weekend_days <- ctx$calendar$day_idx[ctx$calendar$is_weekend &
                                         !ctx$calendar$is_holiday]
  if (length(weekend_days) > 0) {
    weekend_groups <- split(
      weekend_days,
      format(ctx$calendar$date[ctx$calendar$day_idx %in% weekend_days], "%G-W%V")
    )
    total_weekends <- length(weekend_groups)
    N_w <- total_weekends
    cap <- max(0L, total_weekends - ctx$rules$limits$min_free_weekends_per_month)
    # Add the auxiliary variable once over the full (op, w) domain.
    m <- ompr::add_variable(m,
      weekend_worked[op_w, w_idx],
      op_w = 1:N_op, w_idx = 1:N_w, type = "binary")
    for (op_i in 1:N_op) {
      for (w in seq_along(weekend_groups)) {
        days_in_w <- weekend_groups[[w]]
        # Tight per-x link: weekend_worked >= each x in the group.
        for (d in days_in_w) {
          n_slots_d <- nrow(ctx$calendar$slots[[d]])
          for (s in seq_len(n_slots_d)) {
            for (rp in 1:2) {
              m <- ompr::add_constraint(m,
                weekend_worked[op_i, w] >= x[op_i, d, s, rp]
              )
            }
          }
        }
      }
      m <- ompr::add_constraint(m,
        ompr::sum_over(weekend_worked[op_i, w], w = 1:N_w) <= cap
      )
    }
  }

  # H9: senior monthly cap (counted as role_pos = 1 only).
  senior_cap <- ctx$rules$limits$senior_max_per_month
  for (op_i in senior_idx) {
    m <- ompr::add_constraint(m,
      ompr::sum_over(x[op_i, d, s, 1], d = 1:N_day, s = 1:max_slots) <= senior_cap
    )
  }

  # H10: hard preferences (preferences$hard == TRUE) zero matching slots.
  if (!is.null(ctx$preferences) && nrow(ctx$preferences) > 0) {
    for (i in seq_len(nrow(ctx$preferences))) {
      pref <- ctx$preferences[i, ]
      if (!isTRUE(pref$hard)) next
      op_match <- ctx$operators$op_idx[
        ctx$operators$operator_id == pref$operator_id |
        ctx$operators$surname == pref$operator_id
      ]
      if (length(op_match) == 0) next
      day_match <- if (is.na(pref$weekday)) {
        seq_len(N_day)
      } else {
        ctx$calendar$day_idx[ctx$calendar$weekday == pref$weekday]
      }
      for (op_a in op_match) {
        for (d in day_match) {
          slots_today <- ctx$calendar$slots[[d]]
          slot_match <- if (is.na(pref$slot_type)) {
            seq_len(nrow(slots_today))
          } else {
            which(slots_today$period == pref$slot_type)
          }
          if (length(slot_match) == 0) next
          if (pref$polarity == "avoid") {
            m <- ompr::add_constraint(m,
              ompr::sum_over(x[op_a, d, s, rp], s = slot_match, rp = 1:2) == 0
            )
          }
          # "prefer + hard" rare; v1 doesn't enforce as a must-work.
        }
      }
    }
  }

  # ---------------------------------------------------------------------
  # SOFT OBJECTIVE
  # Tier 1: monthly-total dispersion within role group (senior, second).
  # Tier 2: weekend+holiday count deviation per operator from group mean.
  # Tier 3: soft preferences (hard == FALSE) -- penalize matching x.
  # Tier 4: smoothness -- DEFERRED to v1.1 (linearization required).
  # ---------------------------------------------------------------------
  fw <- ctx$rules$fairness_weights

  # Tier 1: introduce t_max[g], t_min[g] for each role group.
  groups <- list(
    senior = senior_idx,
    second = seq_len(N_op)  # any operator may take role_pos = 2
  )
  N_g <- length(groups)
  m <- ompr::add_variable(m, t_max[g_idx], g_idx = 1:N_g,
                          type = "continuous", lb = 0)
  m <- ompr::add_variable(m, t_min[g_idx], g_idx = 1:N_g,
                          type = "continuous", lb = 0)
  for (gi in seq_along(groups)) {
    op_set <- groups[[gi]]
    rp_set <- if (gi == 1L) 1L else 2L
    if (length(op_set) == 0) next
    for (op_i in op_set) {
      m <- ompr::add_constraint(m,
        t_max[gi] >=
          ompr::sum_over(x[op_i, d, s, rp_set],
                         d = 1:N_day, s = 1:max_slots)
      )
      m <- ompr::add_constraint(m,
        t_min[gi] <=
          ompr::sum_over(x[op_i, d, s, rp_set],
                         d = 1:N_day, s = 1:max_slots)
      )
    }
  }

  # Tier 2: weekend/holiday equity. Per-op deviation from group mean.
  we_h_days <- ctx$calendar$day_idx[ctx$calendar$is_weekend |
                                       ctx$calendar$is_holiday]
  m <- ompr::add_variable(m, we_dev[op_d], op_d = 1:N_op,
                          type = "continuous", lb = 0)
  if (length(we_h_days) > 0) {
    for (gi in seq_along(groups)) {
      op_set <- groups[[gi]]
      group_size <- length(op_set)
      if (group_size == 0) next
      total_we_slots <- sum(purrr::map_int(we_h_days, function(d)
        nrow(ctx$calendar$slots[[d]])))
      # group mean approximation (split equally across the group).
      mean_we <- total_we_slots / group_size
      for (op_i in op_set) {
        m <- ompr::add_constraint(m,
          we_dev[op_i] >=
            ompr::sum_over(x[op_i, d, s, rp],
                           d = we_h_days, s = 1:max_slots, rp = 1:2)
            - mean_we
        )
        m <- ompr::add_constraint(m,
          we_dev[op_i] >=
            mean_we -
            ompr::sum_over(x[op_i, d, s, rp],
                           d = we_h_days, s = 1:max_slots, rp = 1:2)
        )
      }
    }
  }

  # Tier 3: soft preferences. For each soft "avoid" preference row, add a
  # continuous penalty variable bounded below by the matching x-sum so that
  # any matching assignment incurs cost.
  pref_terms <- list()
  if (!is.null(ctx$preferences) && nrow(ctx$preferences) > 0) {
    for (i in seq_len(nrow(ctx$preferences))) {
      pref <- ctx$preferences[i, ]
      if (isTRUE(pref$hard)) next
      op_match <- ctx$operators$op_idx[
        ctx$operators$operator_id == pref$operator_id |
        ctx$operators$surname == pref$operator_id
      ]
      if (length(op_match) == 0) next
      day_match <- if (is.na(pref$weekday)) seq_len(N_day) else
        ctx$calendar$day_idx[ctx$calendar$weekday == pref$weekday]
      for (op_a in op_match) {
        for (d in day_match) {
          slots_today <- ctx$calendar$slots[[d]]
          slot_match <- if (is.na(pref$slot_type)) {
            seq_len(nrow(slots_today))
          } else {
            which(slots_today$period == pref$slot_type)
          }
          if (length(slot_match) == 0) next
          if (pref$polarity == "avoid") {
            pref_terms[[length(pref_terms) + 1]] <- list(
              op = op_a, day = d, slots = slot_match
            )
          }
        }
      }
    }
  }

  N_pref <- length(pref_terms)
  if (N_pref > 0) {
    m <- ompr::add_variable(m, pref_pen[p_idx], p_idx = 1:N_pref,
                            type = "continuous", lb = 0)
    for (pi in seq_along(pref_terms)) {
      pt <- pref_terms[[pi]]
      m <- ompr::add_constraint(m,
        pref_pen[pi] >=
          ompr::sum_over(x[pt$op, pt$day, s, rp], s = pt$slots, rp = 1:2)
      )
    }
  }

  # Compose objective.
  if (N_pref > 0) {
    m <- ompr::set_objective(m,
      fw$monthly_total *
        ompr::sum_over(t_max[g_idx] - t_min[g_idx], g_idx = 1:N_g) +
      fw$weekend_holiday *
        ompr::sum_over(we_dev[op_d], op_d = 1:N_op) +
      fw$preference *
        ompr::sum_over(pref_pen[p_idx], p_idx = 1:N_pref),
      sense = "min"
    )
  } else {
    m <- ompr::set_objective(m,
      fw$monthly_total *
        ompr::sum_over(t_max[g_idx] - t_min[g_idx], g_idx = 1:N_g) +
      fw$weekend_holiday *
        ompr::sum_over(we_dev[op_d], op_d = 1:N_op),
      sense = "min"
    )
  }

  m
}
