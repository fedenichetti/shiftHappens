#' @keywords internal
"_PACKAGE"

## Package-level import declarations.
##
## All package dependencies are accessed via `::` throughout the codebase,
## so only a minimal set of imports is declared here.  The imports below
## satisfy R CMD check ("no visible binding for global variable") for .data
## and the `%||%` operator, and prevent "namespace not declared" NOTEs for
## packages that are used only via `::`.
##
## htmltools is imported so that `htmltools::div` / `htmltools::tags$*`
## calls in ui_helpers.R resolve correctly when the package is installed.

#' @importFrom rlang .data %||%
#' @importFrom htmltools div tags
NULL

## ROI.plugin.glpk registers the GLPK solver with the ROI solver registry
## as a side effect of being loaded.  Because the package is accessed only
## via `::` in model_solve.R (ompr.roi::with_ROI(solver="glpk", ...)),
## R's lazy namespace loading would not trigger registration in time.
## The .onLoad hook below ensures the plugin is loaded — and the solver
## therefore registered — whenever shifthappens is attached.
.onLoad <- function(libname, pkgname) {
  loadNamespace("ROI.plugin.glpk")
}
