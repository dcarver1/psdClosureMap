# 03b_census_interpolate.R -- decennial population inside each current attendance boundary
# Method: area-weighted interpolation of block counts (sf::st_interpolate_aw, extensive).
# Blocks are far smaller than attendance zones, so the area weighting affects only edge blocks.
# Each decade uses its own block geometry (blocks are redrawn every census).
# Caveat: 2020 block counts carry differential-privacy noise; sums over a zone are reliable,
# individual blocks are not. Population 18+ is a published table in all three years, so
# under-18 = total - 18+ is exact (pre-noise) rather than derived from age bins.
source(file.path(if (basename(getwd()) == "R") "." else "R", "00_setup.R"))

bnd <- st_read(file.path(dir_proc, "boundaries_current.gpkg"), quiet = TRUE) %>% st_transform(crs_utm)
dist <- st_read(file.path(dir_proc, "psd_district_boundary.gpkg"), quiet = TRUE) %>% st_transform(crs_utm) %>%
  transmute(level = "District", name = name, school = "PSD", status = "district")
# Every zone at every level, plus the whole district as one extra "zone" for the district-wide totals.
zones <- bind_rows(bnd %>% select(level, name, school, status), dist) %>%
  mutate(zone_id = row_number(), zone_area_sqmi = as.numeric(st_area(geom)) / 2589988.11)

years <- c(2000L, 2010L, 2020L)
pop <- map_dfr(years, function(yr) {
  b <- st_read(file.path(dir_proc, paste0("blocks_", yr, ".gpkg")), quiet = TRUE) %>%
    st_make_valid() %>% filter(total > 0)                # empty blocks contribute nothing
  aw <- suppressWarnings(st_interpolate_aw(b[, c("total", "under18")], zones, extensive = TRUE))
  st_drop_geometry(aw) %>% mutate(zone_id = zones$zone_id, year = yr)
})

pop_long <- zones %>% st_drop_geometry() %>%
  inner_join(pop, by = "zone_id") %>%
  mutate(total = round(total), under18 = round(under18), pct_under18 = round(100 * under18 / total, 1)) %>%
  select(level, name, school, status, year, total, under18, pct_under18, zone_area_sqmi) %>%
  arrange(level, name, year)

pop_wide <- pop_long %>%
  select(level, name, status, year, total, under18) %>%
  pivot_wider(names_from = year, values_from = c(total, under18)) %>%
  mutate(
    total_chg_2000_2010   = total_2010 - total_2000,
    total_chg_2010_2020   = total_2020 - total_2010,
    total_pct_2000_2020   = round(100 * (total_2020 / total_2000 - 1), 1),
    under18_chg_2000_2010 = under18_2010 - under18_2000,
    under18_chg_2010_2020 = under18_2020 - under18_2010,
    under18_pct_2000_2020 = round(100 * (under18_2020 / under18_2000 - 1), 1),
    under18_pct_2010_2020 = round(100 * (under18_2020 / under18_2010 - 1), 1),
    share_under18_2000 = round(100 * under18_2000 / total_2000, 1),
    share_under18_2020 = round(100 * under18_2020 / total_2020, 1)
  ) %>% arrange(level, name)

write_csv(pop_long, file.path(dir_out, "census_decennial_by_boundary_long.csv"))
write_csv(pop_wide, file.path(dir_out, "census_decennial_by_boundary_wide.csv"))

# sanity: district total vs county total (the district holds most, not all, of Larimer County's residents)
cnty <- map_dfr(years, ~ st_read(file.path(dir_proc, paste0("blocks_", .x, ".gpkg")), quiet = TRUE) %>%
                  st_drop_geometry() %>% summarise(year = .x, county_total = sum(total), county_under18 = sum(under18)))
print(pop_long %>% filter(level == "District") %>% select(year, total, under18) %>% inner_join(cnty, by = "year"))

cat("\nClosing + receiving elementary zones, under-18 population:\n")
print(pop_wide %>% filter(status %in% c("closing", "receiving", "boundary_change")) %>%
        select(level, name, status, under18_2000, under18_2010, under18_2020, under18_pct_2010_2020), n = 40)
