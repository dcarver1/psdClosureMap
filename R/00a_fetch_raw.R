# 00a_fetch_raw.R -- download every raw input from its public source.
# By default only missing files are fetched, so the archived copies in data/raw (the ones the published page
# was built from) are kept. Set REFRESH=true to re-download everything, e.g. after the district updates a layer:
#   REFRESH=true Rscript R/00a_fetch_raw.R
# Census blocks are fetched separately by 03a_census_fetch.R (needs a free CENSUS_API_KEY).
source(file.path(if (basename(getwd()) == "R") "." else "R", "00_setup.R"))

refresh <- tolower(Sys.getenv("REFRESH")) %in% c("true", "1", "yes")
ua <- c("User-Agent" = "Mozilla/5.0 (psd-closure-map reproducibility script)")
need <- function(f) refresh || !file.exists(f)
get_file <- function(url, dest) {
  if (!need(dest)) return(invisible(FALSE))
  dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)
  message("fetch ", basename(dest))
  download.file(url, dest, mode = "wb", quiet = TRUE, headers = ua)
  invisible(TRUE)
}

# ---- PSD public ArcGIS Online services -----------------------------------------------------
arc <- "https://services.arcgis.com/VBzywyYzcLrfMMGa/arcgis/rest/services"
arc_q <- function(svc, layer) sprintf("%s/%s/FeatureServer/%d/query?where=1%%3D1&outFields=*&outSR=4326&f=geojson", arc, svc, layer)
for (l in 0:2) get_file(arc_q("Boundaries2022", l), file.path(dir_raw, "psd_arcgis", sprintf("Boundaries2022_layer%d.geojson", l)))
get_file(arc_q("Schools_PSD", 0),  file.path(dir_raw, "psd_arcgis", "Schools_PSD.geojson"))
get_file(arc_q("PSD_Boundary", 0), file.path(dir_raw, "psd_arcgis", "PSD_Boundary.geojson"))

# ---- NCES EDGE public school geocodes 2024-25 (for NCES school ids) --------------------------
get_file(paste0("https://nces.ed.gov/opengis/rest/services/K12_School_Locations/EDGE_GEOCODE_PUBLICSCH_2425/MapServer/0/query",
                "?where=LEAID%3D%270803990%27&outFields=*&outSR=4326&f=geojson"),
         file.path(dir_raw, "nces", "edge_geocode_publicsch_2425_psd.geojson"))

# ---- NCES Common Core of Data via the Urban Institute Education Data API ----------------------
edu <- "https://educationdata.urban.org/api/v1/schools/ccd"
for (yr in c(2000, 2010))
  get_file(sprintf("%s/directory/%d/?leaid=0803990", edu, yr), file.path(dir_raw, "nces", sprintf("urban_ccd_school_directory_psd_%d.json", yr)))
# Grade-level counts are only served state-wide; keep PSD rows (the API stores the LEA id without its leading zero).
grade_file <- function(yr, grade, tag) {
  dest <- file.path(dir_raw, "nces", sprintf("urban_ccd_enrollment_%s_psd_%d.json", tag, yr))
  if (!need(dest)) return(invisible())
  message("fetch ", basename(dest))
  url <- sprintf("%s/enrollment/%d/%s/?fips=8", edu, yr, grade)
  d <- fromJSON(url)
  stopifnot(is.null(d$`next`))
  r <- d$results %>% filter(sub("^0+", "", as.character(leaid)) == "803990", race == 99, sex == 99)
  write_json(list(year = yr, source = paste0(sub("^https://", "", url), ", filtered to leaid 803990"), results = r),
             dest, auto_unbox = TRUE, digits = NA)
}
grade_file(2000, "grade-pk", "pk"); grade_file(2010, "grade-pk", "pk"); grade_file(2000, "grade-6", "g6")

# ---- PSD Comprehensive Planning Committee documents (archived as published 2026-09-25) --------
psd <- "https://www.psdschools.org/fs/resource-manager/view/"
get_file(paste0(psd, "9c94a1cd-0de3-49b9-9ebb-f3f2128ec379"), file.path(dir_raw, "psd_cpc", "cpc_executive_summary_2026-09-25.pdf"))
get_file(paste0(psd, "a62d419e-f10a-420d-a695-bd52a678df80"), file.path(dir_raw, "psd_cpc", "cpc_recommendation_slides_2026-09-25.pdf"))
get_file("https://www.psdschools.org/community/district-news-details/~board/poudre-school-district-news/post/psd-comprehensive-planning-committee-recommendation-released",
         file.path(dir_raw, "psd_cpc", "superintendent_announcement_2026-09-25.html"))

# Per-page text of the two PDFs, used by 00b_check_sources.R to verify quotes and page citations.
pdf_pages <- function(pdf, outdir) {
  if (!refresh && dir.exists(outdir) && length(list.files(outdir))) return(invisible())
  dir.create(outdir, showWarnings = FALSE, recursive = TRUE)
  if (requireNamespace("pdftools", quietly = TRUE)) {
    txt <- pdftools::pdf_text(pdf)
    for (i in seq_along(txt)) writeLines(txt[i], file.path(outdir, sprintf("page_%02d.txt", i)))
  } else if (nzchar(Sys.which("mutool"))) {
    n <- as.integer(sub(".*Pages: *([0-9]+).*", "\\1", paste(system2("mutool", c("info", shQuote(pdf)), stdout = TRUE), collapse = " ")))
    for (i in seq_len(n)) system2("mutool", c("draw", "-q", "-F", "txt", "-o", shQuote(file.path(outdir, sprintf("page_%02d.txt", i))), shQuote(pdf), i))
  } else stop("Install the pdftools R package (or mutool) to extract page text from ", basename(pdf))
  message("page text: ", outdir)
}
pdf_pages(file.path(dir_raw, "psd_cpc", "cpc_executive_summary_2026-09-25.pdf"), file.path(dir_raw, "psd_cpc", "executive_summary_pages"))
pdf_pages(file.path(dir_raw, "psd_cpc", "cpc_recommendation_slides_2026-09-25.pdf"), file.path(dir_raw, "psd_cpc", "slides_pages"))

# ---- Fort Collins city limits (Census cartographic boundary file, places, 2024) --------------
fc_out <- file.path(dir_proc, "fort_collins_city_limits.gpkg")
if (need(fc_out)) {
  message("fetch Fort Collins city limits")
  pl <- tigris::places(state = "CO", year = 2024, cb = TRUE, progress_bar = FALSE)
  st_write(pl[pl$NAME == "Fort Collins", ], fc_out, delete_dsn = TRUE, quiet = TRUE)
}
message("raw inputs present", if (refresh) " (refreshed)" else "")
