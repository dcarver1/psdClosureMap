# 02_boundaries.R -- current attendance boundaries and the district outline
#   PSD ArcGIS "Boundaries2022" service (ES edited 2026-07-08, MS/HS 2026-06-12); layer 0 = ES, 1 = HS, 2 = MS.
#   It is the same source as the Nov-2025 PDF maps PSD publishes.
#   The layer's RIC / RICNC / FCI / NSC / FCA fields are PSD facility and capacity metrics, carried through unchanged.
# Outputs: data/processed/boundaries_current.gpkg, data/processed/psd_district_boundary.gpkg
source(file.path(if (basename(getwd()) == "R") "." else "R", "00_setup.R"))

rd <- function(f) st_read(file.path(dir_raw, f), quiet = TRUE) %>% st_transform(crs_wgs84) %>% st_make_valid()

std_psd <- function(x, level) {
  x %>% transmute(
    level      = level,
    school     = str_squish(School),
    school_full= str_squish(SchoolFull),
    artic_area = if ("ArticArea" %in% names(x)) ArticArea else NA_character_,
    cde_code   = as.character(CDE_Code),
    address    = str_squish(Address),
    RIC = if ("RIC" %in% names(x)) as.numeric(RIC) else NA_real_,
    RICNC = if ("RICNC" %in% names(x)) suppressWarnings(as.numeric(RICNC)) else NA_real_,
    FCI = if ("FCI" %in% names(x)) as.numeric(FCI) else NA_real_,
    NSC = if ("NSC" %in% names(x)) as.numeric(NSC) else NA_real_,
    FCA = if ("FCA" %in% names(x)) as.numeric(FCA) else NA_real_,
    FCA_Remain = if ("FCA_Remain" %in% names(x)) as.numeric(FCA_Remain) else NA_real_
  ) %>% mutate(key = school_key(school_full))
}

cur <- bind_rows(
  std_psd(rd("psd_arcgis/Boundaries2022_layer0.geojson"), "ES"),
  std_psd(rd("psd_arcgis/Boundaries2022_layer2.geojson"), "MS"),
  std_psd(rd("psd_arcgis/Boundaries2022_layer1.geojson"), "HS")
) %>% mutate(vintage = "current_2026")

# Attach the PSD full school name used in the points layer (so every layer joins on one name)
pts <- st_read(file.path(dir_proc, "psd_schools.gpkg"), quiet = TRUE) %>% st_drop_geometry() %>%
  distinct(key, .keep_all = TRUE) %>% select(key, name)
cur <- cur %>% left_join(pts, by = "key")
missing <- cur %>% st_drop_geometry() %>% filter(is.na(name))
if (nrow(missing)) { print(missing %>% select(level, school)); stop("Boundaries without a matching school point (see above).") }

# Status flags from the closure plan in 00_setup.R
cur <- cur %>% mutate(status = case_when(
  name %in% closing_schools   ~ "closing",
  name %in% boundary_change   ~ "boundary_change",
  name %in% receiving_schools ~ "receiving",
  TRUE ~ "no_change"))

st_write(cur, file.path(dir_proc, "boundaries_current.gpkg"), delete_dsn = TRUE, quiet = TRUE)
st_write(rd("psd_arcgis/PSD_Boundary.geojson") %>% transmute(name = "Poudre School District R-1"),
         file.path(dir_proc, "psd_district_boundary.gpkg"), delete_dsn = TRUE, quiet = TRUE)
cat("boundaries:", nrow(cur), "zones;", paste(names(table(cur$status)), table(cur$status), collapse = ", "), "\n")
