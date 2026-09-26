# 03a_census_fetch.R -- download decennial block-level population for Larimer County
# 2000 (SF1), 2010 (SF1), 2020 (PL 94-171). Cached to data/processed/blocks_<year>.gpkg
# Variables: total population and population 18 and over (under-18 = total - 18+).
# The cached blocks are committed, so a Census API key is only needed to re-fetch them.
# PSD is 99.99% inside Larimer County (Weld/Jackson/Grand slivers < 0.25 sq mi combined).
source(file.path(if (basename(getwd()) == "R") "." else "R", "00_setup.R"))
suppressPackageStartupMessages(library(tidycensus))

specs <- list(
  `2000` = list(sumfile = "sf1", vars = c(total = "P001001", adult = "P005001")),
  `2010` = list(sumfile = "sf1", vars = c(total = "P001001", adult = "P010001")),
  `2020` = list(sumfile = "pl",  vars = c(total = "P1_001N", adult = "P3_001N"))
)

for (yr in names(specs)) {
  out <- file.path(dir_proc, paste0("blocks_", yr, ".gpkg"))
  if (file.exists(out)) { message("exists: ", out); next }
  if (!nzchar(Sys.getenv("CENSUS_API_KEY")))
    stop("Missing ", basename(out), ". Get a free key at https://api.census.gov/data/key_signup.html and set CENSUS_API_KEY.")
  message("Fetching ", yr, " blocks ...")
  s <- specs[[yr]]
  b <- get_decennial(
    geography = "block", variables = s$vars, year = as.integer(yr), sumfile = s$sumfile,
    state = "CO", county = "Larimer", geometry = TRUE, output = "wide", cache_table = TRUE
  ) %>%
    mutate(year = as.integer(yr), under18 = total - adult) %>%
    select(GEOID, year, total, adult, under18, geometry) %>%
    st_transform(crs_utm) %>%
    mutate(block_area_m2 = as.numeric(st_area(geometry)))
  message("  ", nrow(b), " blocks; total pop ", sum(b$total), "; under 18 ", sum(b$under18))
  st_write(b, out, delete_dsn = TRUE, quiet = TRUE)
}
message("done")
