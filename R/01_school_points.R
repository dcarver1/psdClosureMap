# 01_school_points.R -- point locations for every PSD school
# Primary source : PSD's own ArcGIS Online "Schools_PSD" layer (edited 2026-01-07),
#                  which carries address, type, capacity, and enrollment 2005-06 .. 2024-25.
# Cross-check    : NCES EDGE geocodes, school year 2024-25 (LEAID 0803990).
# Output         : data/processed/psd_schools.gpkg, psd_schools.csv, psd_enrollment_long.csv
source(file.path(if (basename(getwd()) == "R") "." else "R", "00_setup.R"))

psd_pts <- st_read(file.path(dir_raw, "psd_arcgis", "Schools_PSD.geojson"), quiet = TRUE) %>%
  st_transform(crs_wgs84)

# --- tidy the PSD layer ------------------------------------------------------
schools <- psd_pts %>%
  filter(!is.na(SchoolType), SchoolType != "Admin") %>%
  transmute(
    name        = str_squish(Full_Name),
    long_name   = Long_Name,
    school_type = SchoolType,        # ES, MS, HS, "MS / HS", Option, Charter, PreK
    program     = na_if(str_squish(Program), ""),
    grades      = GradeConfi,
    address     = str_squish(paste0(ADDRESS, ", ", City, ", ", State, " ", Zip)),
    cde_code    = as.character(CDE),
    loc_code    = as.character(LocCode),
    artic_area  = ArticArea,
    yr_built    = Yr_Built,
    capacity    = Capacity,
    utilization = Utilizatio,
    across(starts_with("En_"), ~ .x)
  ) %>%
  # Liberty Common appears twice with one empty stub row; drop rows that have no type
  distinct(name, school_type, .keep_all = TRUE) %>%
  filter(!(name == "Liberty Common Elementary School" & is.na(grades)))

# --- enrollment long table ---------------------------------------------------
enroll_long <- schools %>%
  st_drop_geometry() %>%
  select(name, school_type, starts_with("En_")) %>%
  pivot_longer(starts_with("En_"), names_to = "school_year", values_to = "enrollment") %>%
  mutate(school_year = str_replace(school_year, "En_(\\d{4})_(\\d{2})", "\\1-\\2"),
         fall_year   = as.integer(substr(school_year, 1, 4))) %>%
  filter(!is.na(enrollment)) %>%
  # zero enrollment before a school opened is "not open", not zero students
  group_by(name) %>% mutate(open = cumsum(enrollment > 0) > 0) %>% ungroup() %>%
  filter(open) %>% select(-open)

# --- NCES cross-check ---------------------------------------------------------
nces <- st_read(file.path(dir_raw, "nces", "edge_geocode_publicsch_2425_psd.geojson"), quiet = TRUE) %>%
  st_transform(crs_wgs84) %>%
  transmute(ncessch = NCESSCH, nces_name = NAME, nces_locale = LOCALE, nces_lat = LAT, nces_lon = LON) %>%
  mutate(key = school_key(nces_name))

schools <- schools %>%
  mutate(key = school_key(name))

nces_tbl <- nces %>% st_drop_geometry()
schools <- schools %>%
  left_join(nces_tbl %>% distinct(key, .keep_all = TRUE), by = "key")

# distance between PSD point and NCES point (QA; both should be within ~300 m)
nces_geom <- nces %>% select(key) %>% distinct(key, .keep_all = TRUE)
schools <- schools %>%
  mutate(nces_dist_m = {
    idx <- match(key, nces_geom$key)
    d <- rep(NA_real_, n())
    ok <- !is.na(idx)
    d[ok] <- as.numeric(st_distance(st_geometry(schools)[ok], st_geometry(nces_geom)[idx[ok]], by_element = TRUE))
    round(d)
  })

# --- closure status ---------------------------------------------------------
schools <- schools %>%
  mutate(status = case_when(
    name %in% closing_schools   ~ "closing",
    name %in% consolidating     ~ "consolidating",
    name %in% boundary_change   ~ "boundary_change",
    name %in% receiving_schools ~ "receiving",
    TRUE                        ~ "no_change"
  )) %>%
  mutate(receives_from = map_chr(name, ~ paste(closure_plan$closing[closure_plan$receiving %in% .x & closure_plan$action == "close"], collapse = "; ")),
         sends_to      = map_chr(name, ~ paste(na.omit(closure_plan$receiving[closure_plan$closing == .x]), collapse = "; "))) %>%
  mutate(across(c(receives_from, sends_to), ~ na_if(.x, ""))) %>%
  mutate(lon = st_coordinates(geometry)[, 1], lat = st_coordinates(geometry)[, 2]) %>%
  select(name, long_name, school_type, program, grades, status, sends_to, receives_from,
         address, lat, lon, capacity, utilization, artic_area, yr_built, cde_code, loc_code,
         ncessch, nces_name, nces_locale, nces_dist_m, key, everything())

# --- write ------------------------------------------------------------------
st_write(schools, file.path(dir_proc, "psd_schools.gpkg"), delete_dsn = TRUE, quiet = TRUE)
write_csv(schools %>% st_drop_geometry() %>% select(-starts_with("En_")), file.path(dir_proc, "psd_schools.csv"))
write_csv(enroll_long, file.path(dir_proc, "psd_enrollment_long.csv"))

# --- report -----------------------------------------------------------------
cat("Schools kept:", nrow(schools), "\n")
print(table(schools$school_type, schools$status))
cat("\nUnmatched to NCES:\n"); print(schools %>% st_drop_geometry() %>% filter(is.na(ncessch)) %>% select(name, school_type))
cat("\nNCES schools not matched to PSD layer:\n"); print(nces_tbl %>% filter(!key %in% schools$key) %>% select(nces_name))
cat("\nPSD vs NCES point distance (m):\n"); print(summary(schools$nces_dist_m))
print(schools %>% st_drop_geometry() %>% filter(nces_dist_m > 300) %>% select(name, nces_name, nces_dist_m))
cat("\nClosure plan schools present in point layer:\n")
print(setdiff(unique(c(closure_plan$closing, na.omit(closure_plan$receiving))), schools$name))
