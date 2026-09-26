# 00_setup.R -- shared packages, paths, and the closure plan
# Source this at the top of every numbered script.

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(purrr)
  library(readr)
  library(jsonlite)
})

sf_use_s2(FALSE)
options(tigris_use_cache = TRUE, timeout = 600)

# Anchor on the project root regardless of where Rscript is invoked from
proj_root <- normalizePath(
  if (basename(getwd()) == "R") ".." else ".",
  mustWork = TRUE
)
p <- function(...) file.path(proj_root, ...)
dir_raw  <- p("data", "raw")
dir_proc <- p("data", "processed")
dir_out  <- p("output")
for (d in c(dir_raw, dir_proc, dir_out)) dir.create(d, showWarnings = FALSE, recursive = TRUE)

# Working CRS for area math: Colorado North (US ft) -> use NAD83 / UTM 13N (m)
crs_wgs84 <- 4326
crs_utm   <- 26913

# Poudre School District R-1 identifiers
psd_leaid <- "0803990"   # NCES LEA id
psd_cde   <- "1550"      # Colorado Dept of Education district code

# ---------------------------------------------------------------------------
# Closure / consolidation plan from the 2026-09-25 superintendent email.
# One row per (closing school, receiving school) pair. "note" carries caveats.
# ---------------------------------------------------------------------------
closure_plan <- tribble(
  ~closing,                      ~level, ~receiving,                     ~action,        ~note,
  "Beattie Elementary",          "ES",   "Lopez Elementary",             "close",        "Boundary split between two receivers; split line not yet published",
  "Beattie Elementary",          "ES",   "Bennett Elementary",           "close",        "Boundary split between two receivers; split line not yet published",
  "Irish Elementary",            "ES",   "Cache La Poudre Elementary",   "close",        "Boundary split between two receivers; split line not yet published",
  "Irish Elementary",            "ES",   "Bauder Elementary",            "close",        "Boundary split between two receivers; split line not yet published",
  "Irish Elementary",            "ES",   "Harris Elementary",            "close",        "Optional: a cohort of multilingual learners offered Harris Bilingual Immersion",
  "Johnson Elementary",          "ES",   "Olander Elementary",           "close",        "Boundary split between two receivers; split line not yet published",
  "Johnson Elementary",          "ES",   "McGraw Elementary",            "close",        "Boundary split between two receivers; split line not yet published",
  "Putnam Elementary",           "ES",   "Dunn Elementary",              "close",        "Boundary split between two receivers; split line not yet published",
  "Putnam Elementary",           "ES",   "Tavelli Elementary",           "close",        "Boundary split between two receivers; split line not yet published",
  "Livermore Elementary",        "ES",   "Cache La Poudre Elementary",   "close",        "Mountain school; entire boundary to CLP",
  "Red Feather Elementary",      "ES",   "Cache La Poudre Elementary",   "close",        "Mountain school; entire boundary to CLP",
  "Stove Prairie Elementary",    "ES",   "Cache La Poudre Elementary",   "close",        "Mountain school; entire boundary to CLP",
  "Timnath Elementary",          "ES",   "Linton Elementary",            "close",        "Boundary split between two receivers; split line not yet published",
  "Timnath Elementary",          "ES",   "Bamford Elementary",           "close",        "Boundary split between two receivers; split line not yet published",
  "Bacon Elementary",            "ES",   NA_character_,                  "boundary_change", "Boundary change only; details not yet published",
  "Blevins Middle",              "MS",   "Webber Middle",                "close",        "Boundary split between two receivers; split line not yet published",
  "Blevins Middle",              "MS",   "Lincoln Middle",               "close",        "Boundary split between two receivers; split line not yet published",
  "Centennial HS",               "Option","Poudre Community Academy",    "consolidate",  "Consolidate into a new school; location decided early 2027",
  "Poudre Community Academy",    "Option","Centennial HS",               "consolidate",  "Consolidate into a new school; location decided early 2027"
)

closing_schools   <- unique(closure_plan$closing[closure_plan$action == "close"])
receiving_schools <- unique(na.omit(closure_plan$receiving[closure_plan$action == "close"]))
consolidating     <- unique(closure_plan$closing[closure_plan$action == "consolidate"])
boundary_change   <- unique(closure_plan$closing[closure_plan$action == "boundary_change"])

# Normalize school names across PSD, NCES, SABS, and boundary layers to one join key.
# Level words are kept (so "Timnath Elementary" and "Timnath Middle High" stay distinct);
# only "school(s)" / "jr" / "sr" are dropped and HS/MS/ES abbreviations expanded.
school_key <- function(x) {
  k <- x %>%
    str_to_lower() %>%
    str_replace_all("[-/]", " ") %>%
    str_replace_all("[^a-z0-9 ]", "") %>%
    str_replace_all("\\bhs\\b", "high") %>%
    str_replace_all("\\bms\\b", "middle") %>%
    str_replace_all("\\bes\\b", "elementary") %>%
    str_replace_all("\\b(school|schools|jr|sr)\\b", " ") %>%
    str_squish()
  # aliases: other sources' spellings -> the PSD points-layer spelling
  alias <- c(
    "red feather lakes elementary"   = "red feather elementary",
    "harris bilingual elementary"    = "harris elementary",
    "traut core elementary"          = "traut elementary",
    "kinard core knowledge middle"   = "kinard middle",
    "liberty common charter"         = "liberty common",
    "wellington middle"              = "wellington middle high",
    "psd options"                    = "psd options"
  )
  unname(ifelse(k %in% names(alias), alias[k], k))
}
