# IOV Planner — input validation.
#
# Runs a series of cross-checks on the parsed inputs (from R/iov_parse.R)
# and the resolved roster (from R/iov_roster.R) and returns a structured
# `list(blockers, warnings)`:
#   - blockers: HARD errors that prevent the solver from running. Surfaced
#       in the Shiny validation panel; user must resolve before "Generate"
#       is enabled.
#   - warnings: SOFT issues to surface to the user but allow generation.
#       Logged in the output xlsx metadata sheet.
#
# Public function:
#   - validate_iov_inputs(parsed_inputs, resolved_roster)
#
# All package access is namespace-qualified — no library() calls.
#
# Spec: docs/superpowers/specs/2026-05-21-iov-planner-design.md §5.1 (HARD
# constraints H4, H7) and §5.2 (SOFT constraint S4).

# (functions added in subsequent tasks)
