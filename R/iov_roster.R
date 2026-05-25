# IOV Planner — roster derivation.
#
# Combines parsed inputs (from R/iov_parse.R) with the canonical member list
# in `iov/analysis/IOV_MEMBERS.xlsx` to produce the unified `resolved_roster`
# state described in spec §4.2.
#
# Public functions:
#   - derive_roster(parsed_inputs, members_path, reparto_selection)
#   - read_iov_members(path)
#
# All public functions return tibbles or named lists. No package state is
# mutated. All package access is namespace-qualified — no library() calls.
#
# Spec: docs/superpowers/specs/2026-05-21-iov-planner-design.md §4.2.

# (functions added in subsequent tasks)
