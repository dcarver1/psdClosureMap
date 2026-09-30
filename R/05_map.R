# 05_map.R -- web page with two Leaflet maps of the 2026 PSD closure recommendation
#   Map 1 "The district today": current zones (one level at a time), all schools by level,
#          census under-18 change by elementary zone (2000-2010, 2010-2020, 2000-2020).
#   Map 2 "What the recommendation changes": closing / receiving / boundary-change zones,
#          lines to named receivers, pop-ups quoting the district's stated reason with page citations.
# Output: output/psd_closures_map.html (single self-contained page, ready to host).
# Needs output/utilization_by_school.csv from R/04_utilization.R.
source(file.path(if (basename(getwd()) == "R") "." else "R", "00_setup.R"))
suppressPackageStartupMessages({ library(leaflet); library(htmltools); library(htmlwidgets) })

# ---- data -------------------------------------------------------------------
pts  <- st_read(file.path(dir_proc, "psd_schools.gpkg"), quiet = TRUE) %>% st_transform(crs_wgs84)
bnd  <- st_read(file.path(dir_proc, "boundaries_current.gpkg"), quiet = TRUE) %>% st_transform(crs_wgs84)
dist <- st_read(file.path(dir_proc, "psd_district_boundary.gpkg"), quiet = TRUE) %>% st_transform(crs_wgs84)
fc_city <- st_read(file.path(dir_proc, "fort_collins_city_limits.gpkg"), quiet = TRUE) %>% st_transform(crs_wgs84)  # Census TIGER 2024 place
cens <- read_csv(file.path(dir_out, "census_decennial_by_boundary_wide.csv"), show_col_types = FALSE)
enr  <- read_csv(file.path(dir_proc, "psd_enrollment_long.csv"), show_col_types = FALSE)
util <- read_csv(file.path(dir_out, "utilization_by_school.csv"), show_col_types = FALSE)
rat  <- read_csv(file.path(dir_raw, "psd_cpc", "district_rationale_excerpts.csv"), show_col_types = FALSE)

# 2000-01 enrollment: NCES Common Core of Data (via the Urban Institute Education Data API).
# Federal counts include preschool; PSD's own counts do not. With preschool removed, the federal 2010-11
# counts match PSD's within 3% for 40 of 41 schools. In 2000 PSD elementary schools served K-6 and junior
# highs 7-9, so elementary figures also drop grade 6 (giving K-5, comparable with today); other levels are
# shown with their 2000 grade span rather than adjusted.
read_ccd <- function(f) { r <- fromJSON(file.path(dir_raw, "nces", f))$results
  if (!length(r)) return(tibble(ncessch = character(), n = numeric()))
  tibble(ncessch = sprintf("%012.0f", as.numeric(r$ncessch)), n = pmax(r$enrollment, 0)) }
ccd00 <- fromJSON(file.path(dir_raw, "nces", "urban_ccd_school_directory_psd_2000.json"))$results
pk00  <- read_ccd("urban_ccd_enrollment_pk_psd_2000.json") %>% rename(pk = n)
g600  <- read_ccd("urban_ccd_enrollment_g6_psd_2000.json") %>% rename(g6 = n)
gr_lab <- function(g) ifelse(g <= 0, "K", as.character(g))
by_name00 <- c("LIVERMORE" = "Livermore Elementary", "RED FEATHER" = "Red Feather Elementary", "STOVE PRAIRIE" = "Stove Prairie Elementary")
enr00 <- as_tibble(ccd00) %>% select(ncessch, school_name, enrollment, lo = lowest_grade_offered, hi = highest_grade_offered) %>%
  left_join(pk00, by = "ncessch") %>% left_join(g600, by = "ncessch") %>%
  mutate(elem = lo <= 0 & hi == 6,
         k12 = ifelse(enrollment > 0, enrollment - coalesce(pk, 0), NA_real_),
         val = ifelse(elem, k12 - coalesce(g6, 0), k12),
         txt = ifelse(is.na(val), NA_character_,
                      ifelse(elem, formatC(val, format = "d", big.mark = ","),
                             sprintf("%s<br><span class='fine'>gr. %s-%s</span>", formatC(val, format = "d", big.mark = ","), gr_lab(pmax(lo, 0)), hi))),
         name = pts$name[match(ncessch, pts$ncessch)],
         name = coalesce(name, map_chr(school_name, function(s) { h <- by_name00[str_detect(s, names(by_name00))]; if (length(h)) h[[1]] else NA_character_ }))) %>%
  filter(!is.na(name), !is.na(txt)) %>% distinct(name, .keep_all = TRUE) %>% select(name, `2000-01` = txt)

# ---- publishing settings (edit before hosting) ------------------------------------------
# site_url: the page's final public address, e.g. "https://example.com/psd-maps/". Link previews on
#   Facebook and LinkedIn need absolute URLs, so fill this in before sharing.
# corrections_url: optional form or issue tracker for corrections, listed first in the footer (a Google Form needs no
#   account), followed by the repository's GitHub issues page once repo_url is set. Left blank, the footer asks readers
#   to comment where they found the page (the social posts) instead.
site_url        <- "https://psd.carverd.com/"
corrections_url <- "https://docs.google.com/forms/d/e/1FAIpQLSeunRUQFphpf4dvnwrdKYMJJzp_FcK3cJvQexjPYMjW-_vDuQ/viewform"
# repo_url: the public GitHub repository, linked in the footer as the home of the code and data ("" to omit).
repo_url        <- "https://github.com/dcarver1/psdClosureMap"
og_image <- paste0(site_url, "psd_closures_preview.png")
corrections_html <- if (nzchar(corrections_url) && nzchar(repo_url)) {
  sprintf(" Spot an error? <a href='%s'>Send a correction</a> (no account needed), or open an issue on the <a href='%s/issues'>GitHub issues page</a>.",
          corrections_url, sub("/$", "", repo_url))
} else if (nzchar(corrections_url)) {
  sprintf(" Spot an error? <a href='%s'>Send a correction</a> (no account needed).", corrections_url)
} else if (nzchar(repo_url)) {
  sprintf(" Corrections are welcome: comment where you found this page, or open an issue on the <a href='%s/issues'>GitHub issues page</a>.",
          sub("/$", "", repo_url))
} else {
  " Corrections are welcome: comment where you found this page."
}

url_exec <- "https://www.psdschools.org/fs/resource-manager/view/9c94a1cd-0de3-49b9-9ebb-f3f2128ec379"
# PSD's interactive planning dashboard (Power BI "publish to web"). It offers no data export and no
# per-school deep link (publish-to-web ignores URL filters), so it is mentioned once, above the tables and in
# Sources, as a further reference for enrollment change over time. Set url_dashboard to "" to drop the mention.
url_dashboard   <- "https://app.powerbi.com/view?r=eyJrIjoiZjMzY2Y0ZDgtODE2NC00N2E5LTg5YjgtNDMwYmYzOGJhMmMyIiwidCI6IjBkNmQ4NDZjLWVhZGQtNGI2Yy1iMDNlLWYxNWNkNGI3ZTljZiIsImMiOjZ9"
dashboard_title <- "PSD's interactive planning dashboard"

# ---- palette (contrast checked for color-vision deficiency, 2026-09-26) -------------
# Level: three categorical colors that stay distinguishable for common color-vision deficiencies; gray for other programs.
# 6-12 campuses carry both: high-school fill with a middle-school ring.
col_level <- c(ES = "#2a78d6", MS = "#eb6834", HS = "#1baf7a", MSHS = "#1baf7a", Other = "#898781")
ring_level <- c(ES = "#ffffff", MS = "#ffffff", HS = "#ffffff", MSHS = "#eb6834", Other = "#ffffff")
lab_level <- c(ES = "Elementary", MS = "Middle", HS = "High", MSHS = "Middle-high (grades 6-12)", Other = "Choice, charter, preschool")
grp_level <- c(ES = "Elementary schools", MS = "Middle schools", HS = "High schools", Other = "Choice, charter and preschool")
# Status: neutral charcoal for closing (deliberately not red), blue receiving, green consolidating, yellow boundary change.
col_status <- c(closing = "#52514e", receiving = "#2a78d6", consolidating = "#1baf7a", boundary_change = "#eda100")
lab_status <- c(closing = "Recommended to close", receiving = "Named to receive students",
                consolidating = "Recommended to consolidate", boundary_change = "Boundary change")
# Census: brown (fewer children) <-> gray midpoint <-> teal (more children)
cen_breaks <- c(-Inf, -10, -5, -2, 2, 10, 25, Inf)
cen_cols   <- c("#8c510a", "#bf812d", "#dfc27d", "#f0efec", "#80cdc1", "#35978f", "#01665e")
cen_labs   <- c("10% or more fewer", "5 to 10% fewer", "2 to 5% fewer", "Within 2%", "2 to 10% more", "10 to 25% more", "25% or more")
pal_cen    <- function(x) cen_cols[findInterval(x, cen_breaks[-c(1, length(cen_breaks))]) + 1]

# ---- helpers -----------------------------------------------------------------
# Number formatting for pop-ups and tables ("n/a" for missing), short school names, and page-linked citations
# to the executive summary (PDF viewers honor #page=N).
fmt  <- function(x, d = 0) ifelse(is.na(x), "n/a", formatC(x, format = "f", digits = d, big.mark = ","))
pct  <- function(x) ifelse(is.na(x), "n/a", paste0(round(100 * x), "%"))
sgn  <- function(x) ifelse(is.na(x), "n/a", paste0(formatC(round(x), format = "d", big.mark = ",", flag = "+"), "%"))
usd  <- function(x) ifelse(is.na(x), "", sprintf("$%.1fM", x / 1e6))
short <- function(x) str_remove(x, " (Elementary|Middle|HS|Middle High School)$")
lvl_of <- function(t) case_when(t == "ES" ~ "ES", t == "MS" ~ "MS", t == "HS" ~ "HS", t == "MS / HS" ~ "MSHS", TRUE ~ "Other")
cite  <- function(page, short = FALSE) sprintf("<a href='%s#page=%s' target='_blank' rel='noopener'>%sp. %s</a>", url_exec, page,
                                              ifelse(short, "", "PSD CPC executive summary, "), page)
dash_a <- function(txt = dashboard_title) if (nzchar(url_dashboard)) sprintf("<a href='%s' target='_blank' rel='noopener'>%s</a>", url_dashboard, txt) else ""

# Enrollment years shown in pop-ups: 2000-01 from NCES (above), the rest from PSD's points layer.
yrs <- c("2000-01", "2010-11", "2015-16", "2019-20", "2024-25")
enr_wide <- enr %>% filter(school_year %in% yrs) %>% select(name, school_year, enrollment) %>%
  pivot_wider(names_from = school_year, values_from = enrollment) %>%
  mutate(across(everything() & !name, ~ ifelse(is.na(.x), NA_character_, formatC(.x, format = "d", big.mark = ",")))) %>%
  full_join(enr00, by = "name") %>% select(name, any_of(yrs))
enr_row <- function(nm) {
  e <- enr_wide %>% filter(name == nm)
  if (nrow(e) == 0) return("")
  v <- map_chr(yrs, function(y) if (y %in% names(e) && !is.na(e[[y]])) e[[y]] else "&ndash;")
  paste0("<table><tr><th colspan='5' style='text-align:left'>Enrollment</th></tr><tr>",
         paste0("<th>", yrs, "</th>", collapse = ""), "</tr><tr>", paste0("<td>", v, "</td>", collapse = ""), "</tr></table>",
         "<div class='fine'>2000-01 is federal NCES data without preschool. Elementary schools then served K-6, so grade 6 is removed; other levels show their 2000 grades. Later years are PSD's counts. &ndash; means not open or not reported under this name.</div>")
}
chg_or_note <- function(base, pctv) if (is.na(base) || base <= 0) "no base" else sgn(pctv)
census_rows <- function(nm, lv) {
  r <- cens %>% filter(name == nm, level == lv)
  if (nrow(r) == 0) return("")
  sprintf("<table><tr><th>Living in this zone</th><th>2000</th><th>2010</th><th>2020</th><th>2000-20</th><th>2010-20</th></tr>
           <tr><td>All residents</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>
           <tr><td>Under 18</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr></table>",
          fmt(r$total_2000), fmt(r$total_2010), fmt(r$total_2020),
          sgn(100 * (r$total_2020 / r$total_2000 - 1)), sgn(100 * (r$total_2020 / r$total_2010 - 1)),
          fmt(r$under18_2000), fmt(r$under18_2010), fmt(r$under18_2020),
          chg_or_note(r$under18_2000, 100 * (r$under18_2020 / r$under18_2000 - 1)),
          chg_or_note(r$under18_2010, 100 * (r$under18_2020 / r$under18_2010 - 1)))
}
fine_census <- "<div class='fine'>Census counts are area-weighted estimates from 2000, 2010 and 2020 census blocks, so they are approximate. Percentages from a very small starting count can be large. Where children live is not the same as where they attend school.</div>"

# ---- school table ------------------------------------------------------------------
# One row per school with its working capacity and, for recommended schools, the district's quoted reason.
# popup_school() builds the HTML pop-up for each school; its content depends on the school's status.
sch <- pts %>% mutate(lvl = lvl_of(school_type)) %>%
  left_join(util %>% select(name, nsc_cap, util_nsc, capacity_source), by = "name") %>%
  left_join(rat, by = c("name" = "school"))
sch_df <- sch %>% st_drop_geometry()

recv_of <- function(nm) closure_plan %>% filter(closing == nm, !is.na(receiving)) %>% pull(receiving)
from_of <- function(nm) closure_plan %>% filter(receiving == nm, action == "close") %>% pull(closing)

popup_school <- function(nm) {
  r <- sch_df %>% filter(name == nm) %>% slice(1)
  if (nrow(r) == 0) return(nm)
  cap_src <- if (isTRUE(r$capacity_source == "cpc_exec_summary")) "from the executive summary"
             else if (isTRUE(str_starts(r$capacity_source, "derived"))) "derived from PSD's boundary map layer"
             else "estimated from the older capacity field in PSD's school layer"
  cap_line <- if (!is.na(r$nsc_cap)) sprintf("<div>Working capacity: %s students (%s). Use in 2024-25: %s.</div>", fmt(r$nsc_cap), cap_src, pct(r$util_nsc)) else ""
  head <- sprintf("<div class='pp'><h4>%s</h4><div class='sub'>%s &middot; grades %s</div>", nm, lab_level[lvl_of(r$school_type)], r$grades)
  body <- switch(r$status,
    closing = {
      rc <- recv_of(nm); rc_main <- rc[!str_detect(rc, "Harris")]
      paste0("<div class='st'>", lab_status["closing"], "</div>",
             "<div>Students assigned to ", paste(rc_main, collapse = " and "),
             ifelse(any(str_detect(rc, "Harris")), "; a cohort of multilingual learners will be offered Harris Bilingual Immersion", ""), ".</div>",
             if (!is.na(r$rationale_excerpt)) paste0("<blockquote>&ldquo;", htmlEscape(r$rationale_excerpt), "&rdquo;</blockquote><div class='cite'>", cite(r$rationale_page), "</div>") else "",
             enr_row(nm), cap_line,
             if (!is.na(r$deferred_maintenance_usd)) sprintf("<div>Deferred maintenance estimate: %s (%s)</div>", usd(r$deferred_maintenance_usd), cite(r$deferred_maintenance_page, TRUE)) else "",
             if (!is.na(r$operating_savings)) sprintf("<div>Estimated operating savings: %s (%s)</div>", r$operating_savings, cite(r$savings_page, TRUE)) else "")
    },
    consolidating = paste0("<div class='st'>", lab_status["consolidating"], "</div>",
             "<div>Centennial and Poudre Community Academy would combine into one alternative education campus. The location is to be decided in early 2027.</div>",
             "<blockquote>&ldquo;", htmlEscape(r$rationale_excerpt), "&rdquo;</blockquote><div class='cite'>", cite(r$rationale_page), "</div>",
             enr_row(nm), cap_line,
             sprintf("<div>Deferred maintenance estimate: %s (%s)</div>", usd(r$deferred_maintenance_usd), cite(r$deferred_maintenance_page, TRUE)),
             sprintf("<div>Estimated operating savings: %s</div>", r$operating_savings)),
    receiving = {
      fr <- from_of(nm)
      paste0("<div class='st'>", lab_status["receiving"], "</div>",
             "<div>Receives students from ", paste(fr, collapse = ", "),
             ifelse(nm == "Harris Elementary", " (an optional cohort of multilingual learners)", ""), ".</div>",
             enr_row(nm), cap_line,
             if (nm != "Harris Elementary") "<div class='fine'>How many students each receiver gains depends on where the closing zones are divided, which the district has not yet published.</div>" else "")
    },
    boundary_change = paste0("<div class='st'>", lab_status["boundary_change"], "</div>",
             "<blockquote>&ldquo;", htmlEscape(r$rationale_excerpt), "&rdquo;</blockquote><div class='cite'>", cite(r$rationale_page), "</div>",
             enr_row(nm), cap_line,
             "<div class='fine'>The grid-code areas are not published as map data, so the change is not drawn.</div>"),
    paste0(enr_row(nm), cap_line)
  )
  paste0(head, body, "<div class='fine'>", r$address, "</div></div>")
}
sch$popup <- map_chr(sch$name, popup_school)
sch <- sch %>% mutate(fillc = unname(col_level[lvl]), ringc = unname(ring_level[lvl]),
                      ringw = ifelse(lvl == "MSHS", 3, 1.5),
                      rad = case_when(lvl %in% c("HS", "MSHS") ~ 7, lvl == "MS" ~ 6, TRUE ~ 5),
                      label = paste0(name, " (", lab_level[lvl], ")"))

# ---- shared controls ----------------------------------------------------------------------
bb_dist <- st_bbox(dist); bb_fc <- st_bbox(fc_city)
nav_buttons <- function(m) m %>%
  addEasyButton(easyButton(title = "Show all of Poudre School District R-1", icon = "<span>Poudre School District R-1</span>",
    onClick = JS(sprintf("function(btn, map){ map.fitBounds([[%f,%f],[%f,%f]]); }", bb_dist$ymin, bb_dist$xmin, bb_dist$ymax, bb_dist$xmax)))) %>%
  addEasyButton(easyButton(title = "Zoom to the Fort Collins city limits (Census 2024)", icon = "<span>Fort Collins city limits</span>",
    onClick = JS(sprintf("function(btn, map){ map.fitBounds([[%f,%f],[%f,%f]]); }", bb_fc$ymin, bb_fc$xmin, bb_fc$ymax, bb_fc$xmax))))
# JavaScript run once each map renders (htmlwidgets::onRender):
#   heads          list of c(first label in a section, section title) pairs; a title is inserted above that label.
#                  Leaflet rebuilds the layer list whenever a layer is toggled, so titles are re-added each time.
#   exclusive      overlay groups that behave like radio buttons (turning one on turns the others off).
#   legend_groups  groups whose legend box (class legend-cen) is shown only while one of them is on.
# The layer menu starts expanded on screens wider than 700 px and collapsed on phones.
layer_js <- function(heads, exclusive = character(), legend_groups = character()) {
  sprintf("function(el, x){
    var map = this, heads = %s, excl = %s, lg = %s, box = el.querySelector('.legend-cen');
    function grp(n){ return map.layerManager.getLayerGroup(n); }
    function addHeads(){
      var list = el.querySelector('.leaflet-control-layers-list'); if (!list) return;
      list.querySelectorAll('.lc-head').forEach(function(h){ h.remove(); });
      heads.forEach(function(h){
        var labels = list.querySelectorAll('label');
        for (var i = 0; i < labels.length; i++) if (labels[i].textContent.trim() === h[0]) {
          var d = document.createElement('div'); d.className = 'lc-head'; d.textContent = h[1];
          labels[i].parentNode.insertBefore(d, labels[i]); break; }
      });
    }
    function syncLegend(){ if (!box) return; var on = lg.some(function(n){ var g = grp(n); return g && map.hasLayer(g); }); box.style.display = on ? '' : 'none'; }
    map.on('overlayadd', function(e){
      if (excl.indexOf(e.name) >= 0) excl.forEach(function(n){ if (n !== e.name){ var g = grp(n); if (g && map.hasLayer(g)) map.removeLayer(g); } });
      setTimeout(function(){ if (map.currentLayersControl) map.currentLayersControl._update(); addHeads(); syncLegend(); }, 0);
    });
    map.on('overlayremove baselayerchange', function(){ setTimeout(function(){ addHeads(); syncLegend(); }, 0); });
    setTimeout(function(){ addHeads(); syncLegend(); }, 0);
    if (window.innerWidth > 700) el.querySelector('.leaflet-control-layers').classList.add('leaflet-control-layers-expanded');
  }", jsonlite::toJSON(heads), jsonlite::toJSON(exclusive), jsonlite::toJSON(legend_groups))
}

# ---- map 1: the district today --------------------------------------------------------
popup_zone1 <- function(nm, lv) paste0("<div class='pp'><h4>", nm, "</h4><div class='sub'>", lab_level[lv], " attendance zone</div>",
                                       enr_row(nm), census_rows(nm, lv), fine_census, "</div>")
bnd1 <- bnd %>% mutate(popup = map2_chr(name, level, popup_zone1)) %>%
  left_join(cens %>% select(name, level, under18_2000, under18_2010, under18_2020), by = c("name", "level"))
cen_layers <- tribble(~grp, ~from, ~to,
  "Change, 2000 to 2020", 2000, 2020,
  "Change, 2000 to 2010", 2000, 2010,
  "Change, 2010 to 2020", 2010, 2020)
cen_poly <- function(from, to) {
  bnd1 %>% filter(level == "ES") %>%
    mutate(base = .data[[paste0("under18_", from)]], end = .data[[paste0("under18_", to)]],
           ok = !is.na(base) & base > 0, chg = ifelse(ok, 100 * (end / base - 1), NA_real_),
           fill = ifelse(ok, pal_cen(chg), "#d9d8d4"),
           tip = ifelse(ok, sprintf("%s zone: %s children under 18, %d to %d (%s to %s)", short(name), sgn(chg), from, to,
                                    formatC(base, format = "d", big.mark = ","), formatC(end, format = "d", big.mark = ",")),
                            sprintf("%s zone: no residents under 18 recorded in %d, so no change can be shown", short(name), from)))
}
legend_level <- tags$div(class = "legend-box",
  tags$b("School level"),
  HTML(paste0(sprintf("<span class='dot' style='background:%s;box-shadow:0 0 0 %s %s'></span>%s<br>",
                      col_level, ifelse(names(col_level) == "MSHS", "2.5px", "1px"),
                      ifelse(names(col_level) == "MSHS", "#eb6834", "#898781"), lab_level), collapse = "")))
legend_cen <- tags$div(class = "legend-box",
  tags$b("Children under 18: change by elementary zone"),
  HTML(paste0(sprintf("<span class='box' style='background:%s'></span>%s<br>", cen_cols, cen_labs), collapse = "")),
  if (any(map_lgl(seq_len(nrow(cen_layers)), ~ any(!cen_poly(cen_layers$from[.x], cen_layers$to[.x])$ok))))
    HTML("<span class='box' style='background:#d9d8d4;border:1px dashed #898781'></span>No children recorded in the starting year"))

zones1 <- function(m, lv, group) {
  d <- bnd1 %>% filter(level == lv)
  addPolygons(m, data = d, fill = TRUE, fillColor = col_level[[lv]], fillOpacity = 0.04, color = col_level[[lv]],
              weight = 2, opacity = 0.85, popup = ~popup, label = ~paste(short(name), "zone"), group = group,
              highlightOptions = highlightOptions(weight = 4, fillOpacity = 0.15, bringToFront = FALSE))
}
# Map panes set drawing order: zone outlines (default overlay pane, z 400) < census fill < school points.
m1 <- leaflet(width = "100%", height = 640, options = leafletOptions(minZoom = 8)) %>%
  addMapPane("census", zIndex = 420) %>% addMapPane("schools", zIndex = 450) %>%
  addProviderTiles(providers$Esri.WorldGrayCanvas) %>%
  addPolygons(data = dist, fill = FALSE, color = "#0b0b0b", weight = 1.5, dashArray = "4 6", label = "Poudre School District R-1 boundary") %>%
  zones1("ES", "Elementary zones") %>% zones1("MS", "Middle school zones") %>% zones1("HS", "High school zones")
for (i in seq_len(nrow(cen_layers))) {
  d <- cen_poly(cen_layers$from[i], cen_layers$to[i])
  m1 <- m1 %>% addPolygons(data = d, fillColor = ~fill, fillOpacity = 0.75, color = ~ifelse(ok, "#6f6e69", "#898781"),
                           weight = 0.8, dashArray = ~ifelse(ok, NA, "3 3"), popup = ~popup, label = ~tip, group = cen_layers$grp[i],
                           options = pathOptions(pane = "census"),
                           highlightOptions = highlightOptions(weight = 2.5, bringToFront = FALSE))
}
# 6-12 campuses belong to both the middle and high school groups
pt_groups <- list(ES = "ES", MS = c("MS", "MSHS"), HS = c("HS", "MSHS"), Other = "Other")
for (g in names(pt_groups)) {
  d <- sch %>% filter(lvl %in% pt_groups[[g]])
  m1 <- m1 %>% addCircleMarkers(data = d, radius = ~rad, color = ~ringc, weight = ~ringw, opacity = 1, fillColor = ~fillc,
                                fillOpacity = 1, popup = ~popup, label = ~label, group = grp_level[[g]],
                                options = pathOptions(pane = "schools"))
}
m1 <- m1 %>%
  addControl(legend_level, position = "bottomright") %>%
  addControl(legend_cen, position = "bottomleft", className = "legend-cen") %>%
  addLayersControl(baseGroups = c("Elementary zones", "Middle school zones", "High school zones"),
                   overlayGroups = c(unname(grp_level), cen_layers$grp),
                   options = layersControlOptions(collapsed = TRUE)) %>%
  hideGroup(cen_layers$grp) %>%
  nav_buttons() %>% addScaleBar("bottomleft") %>%
  fitBounds(unname(bb_dist["xmin"]), unname(bb_dist["ymin"]), unname(bb_dist["xmax"]), unname(bb_dist["ymax"])) %>%
  htmlwidgets::onRender(layer_js(
    heads = list(c("Elementary zones", "School District Boundaries"),
                 c("Elementary schools", "School Locations"),
                 c(cen_layers$grp[1], "Decadal Census: Population Under 18, by Elementary Zone")),
    exclusive = cen_layers$grp, legend_groups = cen_layers$grp))

# ---- map 2: what the recommendation changes ---------------------------------------------
popup_zone2 <- function(nm, lv, stt) {
  if (stt == "no_change") return(paste0("<div class='pp'><h4>", nm, "</h4><div class='sub'>No change recommended</div></div>"))
  popup_school(nm)
}
bnd2 <- bnd %>% mutate(popup = pmap_chr(list(name, level, status), popup_zone2),
                       fill = ifelse(status == "no_change", "#ffffff", col_status[status]),
                       fop  = case_when(status == "closing" ~ 0.45, status == "receiving" ~ 0.28, status == "boundary_change" ~ 0.35, TRUE ~ 0),
                       stroke = ifelse(status == "no_change", "#b5b4ad", "#52514e"))
zones2 <- function(m, lv, group) {
  d <- bnd2 %>% filter(level == lv)
  addPolygons(m, data = d, fillColor = ~fill, fillOpacity = ~fop, color = ~stroke, weight = ~ifelse(status == "no_change", 0.8, 1.6),
              opacity = 0.9, popup = ~popup, label = ~ifelse(status == "no_change", paste(short(name), "zone"), paste0(short(name), " zone: ", lab_status[status])),
              group = group, highlightOptions = highlightOptions(weight = 3, fillOpacity = 0.55, bringToFront = FALSE))
}
# Straight dashed lines from each closing school to each named receiver. They show the plan's pairings,
# not routes or final boundary assignments.
pt_xy <- sch_df %>% distinct(name, .keep_all = TRUE) %>% select(name, lon, lat)
lines <- closure_plan %>% filter(!is.na(receiving), action == "close") %>%
  left_join(pt_xy, by = c("closing" = "name")) %>% rename(x0 = lon, y0 = lat) %>%
  left_join(pt_xy, by = c("receiving" = "name")) %>% rename(x1 = lon, y1 = lat) %>% filter(!is.na(x0), !is.na(x1)) %>%
  mutate(geometry = pmap(list(x0, y0, x1, y1), ~ st_linestring(matrix(c(..1, ..3, ..2, ..4), ncol = 2))),
         grp = ifelse(level == "MS", "Middle school changes", "Elementary changes"),
         tip = paste0(short(closing), " to ", short(receiving), ifelse(str_detect(note, "^Optional"), " (optional cohort)", ""))) %>%
  st_as_sf(crs = crs_wgs84)
grp_consol <- "Consolidation (Centennial and PCA)"
aff <- sch %>% filter(status %in% names(col_status)) %>%
  mutate(scol = unname(col_status[status]),
         grp = case_when(status == "consolidating" ~ grp_consol, lvl == "MS" ~ "Middle school changes", TRUE ~ "Elementary changes"),
         label = paste0(short(name), ": ", lab_status[status]))
others <- sch %>% filter(!status %in% names(col_status))

legend_status <- tags$div(class = "legend-box",
  tags$b("Recommendation"),
  HTML(paste0(sprintf("<span class='box' style='background:%s;opacity:.85'></span>%s<br>", col_status, lab_status), collapse = "")),
  HTML("<span class='ln'></span>To each named receiver<br><span class='dot' style='background:#c3c2b7;width:8px;height:8px'></span>Other schools"))

# Drawing order: zones < lines < other schools < affected schools < consolidating schools (always clickable).
m2 <- leaflet(width = "100%", height = 640, options = leafletOptions(minZoom = 8)) %>%
  addMapPane("lines", zIndex = 430) %>% addMapPane("others", zIndex = 440) %>%
  addMapPane("affected", zIndex = 460) %>% addMapPane("consol", zIndex = 470) %>%
  addProviderTiles(providers$Esri.WorldGrayCanvas) %>%
  addPolygons(data = dist, fill = FALSE, color = "#0b0b0b", weight = 1.5, dashArray = "4 6", label = "Poudre School District R-1 boundary") %>%
  zones2("ES", "Elementary changes") %>% zones2("MS", "Middle school changes") %>%
  addCircleMarkers(data = others, radius = 3.5, color = "#ffffff", weight = 1, fillColor = "#c3c2b7", fillOpacity = 1,
                   label = ~name, popup = ~popup, group = "Other schools", options = pathOptions(pane = "others"))
for (g in c("Elementary changes", "Middle school changes")) {
  m2 <- m2 %>% addPolylines(data = lines %>% filter(grp == g), color = "#52514e", weight = 2, opacity = 0.85,
                            dashArray = "6 6", label = ~tip, group = g, options = pathOptions(pane = "lines"))
}
for (g in setdiff(unique(aff$grp), grp_consol)) {
  m2 <- m2 %>% addCircleMarkers(data = aff %>% filter(grp == g), radius = ~rad + 3, color = "#ffffff", weight = 2,
                                fillColor = ~scol, fillOpacity = 1, popup = ~popup, label = ~label, group = g,
                                options = pathOptions(pane = "affected"))
}
# Consolidating schools: largest markers, dark ring, topmost pane so they stay clickable
m2 <- m2 %>% addCircleMarkers(data = aff %>% filter(grp == grp_consol), radius = 11, color = "#0b0b0b", weight = 2.5, opacity = 1,
                              fillColor = col_status[["consolidating"]], fillOpacity = 1, popup = ~popup, label = ~label,
                              group = grp_consol, options = pathOptions(pane = "consol"))
m2 <- m2 %>%
  addControl(legend_status, position = "bottomright") %>%
  addLayersControl(baseGroups = c("Elementary changes", "Middle school changes"),
                   overlayGroups = c(grp_consol, "Other schools"),
                   options = layersControlOptions(collapsed = TRUE)) %>%
  hideGroup(c(grp_consol, "Other schools")) %>%
  nav_buttons() %>% addScaleBar("bottomleft") %>%
  fitBounds(min(aff$lon), min(aff$lat), max(aff$lon), max(aff$lat)) %>%
  htmlwidgets::onRender(layer_js(heads = list(c("Elementary changes", "Recommended Changes"),
                                              c(grp_consol, "Other Layers"))))


# ---- tables under map 2 ----------------------------------------------------------------
html_table <- function(df, num_cols) {
  th <- paste0("<tr>", paste0(sprintf("<th%s>%s</th>", ifelse(names(df) %in% num_cols, " class='num'", ""), names(df)), collapse = ""), "</tr>")
  tr <- apply(df, 1, function(r) paste0("<tr>", paste0(sprintf("<td%s>%s</td>", ifelse(names(df) %in% num_cols, " class='num'", ""), r), collapse = ""), "</tr>"))
  paste0("<table class='data'>", th, paste(tr, collapse = ""), "</table>")
}
# One-line paraphrases of each school's stated reason for the summary table. They are mine, not quotes;
# the full quoted excerpt is in each school's pop-up and every row links to the cited page.
reason_short <- c(
  "Beattie Elementary" = "Enrollment, low utilization, building design, nearby schools",
  "Irish Elementary" = "Declining enrollment; more programming and staff at receivers",
  "Johnson Elementary" = "Ranked first of five southwest schools on a combined enrollment, utilization and facility score",
  "Putnam Elementary" = "Declining enrollment, projected 98 students by 2030-31",
  "Livermore Elementary" = "Remote location, emergency access; more programming at CLP",
  "Red Feather Elementary" = "Remote location, emergency access; more programming at CLP",
  "Stove Prairie Elementary" = "Remote location, emergency access; more programming at CLP",
  "Timnath Elementary" = "Building condition and accessibility (not ADA compliant)",
  "Blevins Middle" = "Low projected enrollment and utilization; two nearby middle schools",
  "Centennial HS" = "Combine two small alternative programs; more staff and electives",
  "Poudre Community Academy" = "Combine two small alternative programs; more staff and electives")
t_close <- sch_df %>% filter(status %in% c("closing", "consolidating")) %>%
  mutate(ord = match(name, names(reason_short))) %>% arrange(ord) %>%
  transmute(School = sprintf("<span class='sw' style='background:%s'></span>%s", col_status[status], name),
            `Students go to` = map_chr(name, ~ if (.x %in% consolidating) "New combined campus (site TBD)" else paste(short(setdiff(recv_of(.x), "Harris Elementary")), collapse = ", ")),
            Enrollment = enr_wide$`2024-25`[match(name, enr_wide$name)],
            `Use of working capacity` = pct(util_nsc),
            `District's main stated reason` = paste0(reason_short[name], " (", cite(rationale_page, TRUE), ")"),
            `Deferred maintenance` = usd(deferred_maintenance_usd))
t_recv <- sch_df %>% filter(status == "receiving", name != "Harris Elementary") %>% arrange(name) %>%
  transmute(School = name, `Receives from` = map_chr(name, ~ paste(short(from_of(.x)), collapse = ", ")),
            `Enrollment, 2024-25` = enr_wide$`2024-25`[match(name, enr_wide$name)],
            `Working capacity` = fmt(nsc_cap), `Use of working capacity` = pct(util_nsc))

# ---- district-wide context ------------------------------------------------------------------
# All district-run schools with a working capacity (the rows of utilization_by_school.csv; charters and a few sites
# without a comparable capacity are excluded in 04_utilization.R). The nine closures remove their buildings' working
# capacity while their students stay in PSD, so district totals do not depend on how closing zones are divided.
# Students stay at the same school level, so open seats by level fall by the closing buildings' capacity at that level.
# The Centennial/PCA consolidation is left out because the campus to be kept is not yet decided.
ctx <- util %>% mutate(grp = case_when(level == "ES" ~ "Elementary", level == "MS" ~ "Middle", level == "HS" ~ "High",
                                       TRUE ~ "Grades 6-12 and alternative"),
                       closing = status == "closing")
ctx_cap <- sum(ctx$nsc_cap); ctx_enr <- sum(ctx$enroll_2024_25); ctx_close_cap <- sum(ctx$nsc_cap[ctx$closing])
ctx_open_now <- ctx_cap - ctx_enr; ctx_open_after <- ctx_open_now - ctx_close_cap
about <- function(x) paste0("about ", formatC(round(x, -2), format = "d", big.mark = ","))
t_ctx <- tibble(` ` = c("Today (2024-25)", "After the nine closures"),
                `Working capacity (seats)` = fmt(c(ctx_cap, ctx_cap - ctx_close_cap)),
                `Students` = fmt(c(ctx_enr, ctx_enr)),
                `Open seats` = fmt(c(ctx_open_now, ctx_open_after)),
                `Use of working capacity` = pct(c(ctx_enr / ctx_cap, ctx_enr / (ctx_cap - ctx_close_cap))))
t_lvl <- ctx %>% group_by(`School level` = grp) %>%
  summarise(now = sum(nsc_cap - enroll_2024_25), after = now - sum(nsc_cap[closing]), .groups = "drop") %>%
  arrange(match(`School level`, c("Elementary", "Middle", "High", "Grades 6-12 and alternative"))) %>%
  transmute(`School level`, `Open seats today` = fmt(now), `Open seats after the closures` = fmt(after))
ctx_hs_after <- with(ctx %>% filter(grp == "High"), sum(nsc_cap - enroll_2024_25) - sum(nsc_cap[closing]))

# ---- page ---------------------------------------------------------------------------------
# Fill the {{ placeholders }} in map_page_template.html. Widget and table arguments must be HTML objects.
page <- htmlTemplate(file.path(proj_root, "R", "map_page_template.html"),
  map1 = m1, map2 = m2, updated = local({ d <- Sys.Date(); sprintf("%s %d, %s", month.name[as.integer(format(d, "%m"))], as.integer(format(d, "%d")), format(d, "%Y")) }),  # English, no %-d (not on Windows)
  n_receivers = length(setdiff(receiving_schools, "Harris Elementary")),
  table_closing = HTML(html_table(t_close, c("Enrollment", "Use of working capacity", "Deferred maintenance"))),
  table_receiving = HTML(html_table(t_recv, c("Enrollment, 2024-25", "Working capacity", "Use of working capacity"))),
  site_url = site_url, og_image = og_image, corrections = HTML(corrections_html),
  code_link = HTML(if (nzchar(repo_url)) sprintf(" Code and data: <a href='%s'>GitHub</a> (code under the MIT license).", repo_url) else ""),
  ctx_n = nrow(ctx), ctx_open_now = about(ctx_open_now), ctx_open_after = about(ctx_open_after),
  ctx_close_cap = about(ctx_close_cap), ctx_use_now = pct(ctx_enr / ctx_cap),
  ctx_use_after = pct(ctx_enr / (ctx_cap - ctx_close_cap)), ctx_hs_after = about(ctx_hs_after),
  table_context = HTML(html_table(t_ctx, names(t_ctx)[-1])),
  table_levels = HTML(html_table(t_lvl, names(t_lvl)[-1])),
  dashboard_note = HTML(if (nzchar(url_dashboard)) paste0(" For another view of how enrollment has changed over time, the district publishes ", dash_a(),
    " (Power BI, opens in a new tab). It cannot be downloaded or linked school by school, so no figure on this page is taken from it.") else ""),
  dashboard_source = HTML(if (nzchar(url_dashboard)) sprintf("<li>PSD, <a href=\"%s\">%s</a> (Power BI, published to the web). A further reference for enrollment change over time. The report offers no download, so no figure on this page is taken from it.</li>", url_dashboard, dashboard_title) else ""))

out <- file.path(dir_out, "psd_closures_map.html")
tmp_dir <- tempfile("mappage"); dir.create(tmp_dir)
tmp <- file.path(tmp_dir, "index.html")
save_html(page, tmp, libdir = "lib")
# Inline every local script, stylesheet and CSS image so the page is one file. (pandoc's
# --self-contained reflows text inside the widget JSON and breaks it, so it is not used.)
inline_page <- function(html_file, out_file) {
  base <- dirname(html_file)
  read_txt <- function(f) paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  mime <- c(png = "image/png", gif = "image/gif", svg = "image/svg+xml", jpg = "image/jpeg", woff = "font/woff", woff2 = "font/woff2")
  css_inline <- function(css, dir) {
    urls <- unique(regmatches(css, gregexpr("url\\(['\"]?[^)'\"]+['\"]?\\)", css))[[1]])
    for (u in urls) {
      path <- gsub("^url\\(['\"]?|['\"]?\\)$", "", u)
      if (grepl("^(data:|https?:|#)", path)) next
      f <- file.path(dir, sub("[?#].*$", "", path)); if (!file.exists(f)) next
      ext <- tolower(tools::file_ext(f))
      uri <- paste0("data:", mime[[ext]], ";base64,", jsonlite::base64_enc(readBin(f, "raw", file.size(f))))
      css <- gsub(u, paste0("url(", uri, ")"), css, fixed = TRUE)
    }
    css
  }
  h <- read_txt(html_file)
  for (tag in regmatches(h, gregexpr("<script src=\"[^\"]+\"></script>", h))[[1]]) {
    src <- sub('.*src="([^"]+)".*', "\\1", tag)
    js <- gsub("</script", "<\\/script", read_txt(file.path(base, src)), fixed = TRUE)
    h <- sub(tag, paste0("<script>", js, "</script>"), h, fixed = TRUE)
  }
  for (tag in regmatches(h, gregexpr("<link href=\"[^\"]+\" rel=\"stylesheet\" />", h))[[1]]) {
    href <- sub('.*href="([^"]+)".*', "\\1", tag); f <- file.path(base, href)
    h <- sub(tag, paste0("<style>", css_inline(read_txt(f), dirname(f)), "</style>"), h, fixed = TRUE)
  }
  stopifnot(!grepl('src="lib/|href="lib/', h))
  writeLines(h, out_file, useBytes = TRUE)
}
inline_page(tmp, out)
unlink(tmp_dir, recursive = TRUE)
cat("wrote", out, " size MB:", round(file.size(out) / 1e6, 1), "\n")
