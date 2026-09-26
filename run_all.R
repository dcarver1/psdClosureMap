# run_all.R -- rebuild the map page from the raw inputs in data/raw
# Usage (from the project root): Rscript run_all.R
# Raw inputs and census blocks are committed, so no downloads or API key are needed for a rebuild.
# To re-download from the public sources first: REFRESH=true Rscript R/00a_fetch_raw.R
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
for (s in scripts) { message("\n==== ", s); source(s, echo = FALSE) }
