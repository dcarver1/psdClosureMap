# run_all.R -- rebuild the map page from the raw inputs in data/raw
# Usage: Rscript run_all.R (from the project root), or source() this file from any working directory.
# Raw inputs and census blocks are committed, so no downloads or API key are needed for a rebuild.
# To re-download from the public sources first: REFRESH=true Rscript R/00a_fetch_raw.R
# Package versions come from renv.lock; start R in this folder (or open psdClosure.Rproj) so .Rprofile
# activates the project library. Otherwise the scripts run against whatever library R finds.

# Work from this file's folder, whether run with Rscript or source()d from elsewhere.
proj_root <- local({
  f <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))   # Rscript run_all.R
  srcd <- unlist(lapply(sys.frames(), function(fr) fr$ofile))                                     # source("run_all.R")
  here <- c(f, srcd, getwd())[1]
  if (dir.exists(here)) normalizePath(here) else dirname(normalizePath(here))
})
if (!file.exists(file.path(proj_root, "R", "00_setup.R"))) stop("R/00_setup.R not found next to run_all.R in ", proj_root)
old_wd <- setwd(proj_root)

scripts <- c(
  "R/00a_fetch_raw.R",          # fills in any missing raw file from its public source
  "R/00b_check_sources.R",      # stops if a quote or page citation no longer matches the district documents
  "R/01_school_points.R",       # PSD school points + NCES ids, enrollment 2005-06 to 2024-25
  "R/02_boundaries.R",          # current attendance zones and district outline, with recommendation status
  "R/03a_census_fetch.R",       # census blocks 2000/2010/2020 (cached; key only needed if missing)
  "R/03b_census_interpolate.R", # area-weighted census counts per zone
  "R/04_utilization.R",         # working and full capacity, utilization, open seats
  "R/05_map.R",                 # the two-map web page -> output/psd_closures_map.html
  "R/06_preview_image.R"        # link-preview image -> output/psd_closures_preview.png
)
tryCatch(for (s in scripts) { message("\n==== ", s); source(s, echo = FALSE) }, finally = setwd(old_wd))
