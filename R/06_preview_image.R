# 06_preview_image.R -- 1200 x 630 link-preview image for Facebook / LinkedIn (og:image)
# Shows the elementary changes only: closing, receiving and boundary-change zones, one point per zone, and an
# arrow from each closing school to each school named to receive its students. The frame is chosen so the
# three mountain schools are in view; unaffected zones are faint outlines. Middle school and consolidation
# changes are left to the page. Harris (optional cohort, no attendance zone) is not drawn.
# Output: output/psd_closures_preview.png. Upload it next to psd_closures_map.html on the website.
source(file.path(if (basename(getwd()) == "R") "." else "R", "00_setup.R"))
suppressPackageStartupMessages({ library(ggplot2); library(grid); library(ragg) })

bnd  <- st_read(file.path(dir_proc, "boundaries_current.gpkg"), quiet = TRUE) %>% st_transform(crs_utm) %>% filter(level == "ES")
pts  <- st_read(file.path(dir_proc, "psd_schools.gpkg"), quiet = TRUE) %>% st_transform(crs_utm) %>%
  filter(school_type == "ES", name %in% bnd$name)          # one point per zone
dist <- st_read(file.path(dir_proc, "psd_district_boundary.gpkg"), quiet = TRUE) %>% st_transform(crs_utm)

col_status   <- c(closing = "#52514e", receiving = "#2a78d6", boundary_change = "#eda100", no_change = "#fcfcfb")
alpha_status <- c(closing = 0.55, receiving = 0.30, boundary_change = 0.40, no_change = 0)
pt_fill      <- c(closing = "#52514e", receiving = "#2a78d6", boundary_change = "#eda100", no_change = "#ffffff")
pt_size      <- c(closing = 3, receiving = 2.5, boundary_change = 2.5, no_change = 2)
mountain     <- c("Livermore Elementary", "Red Feather Elementary", "Stove Prairie Elementary")

aff_z <- bnd %>% filter(status != "no_change")
aff_p <- pts %>% filter(status != "no_change")

# Frame: west and north edges from the affected school points (so the mountain schools are in view), east and
# south edges from the affected zones around Fort Collins (so Timnath and Bacon are not clipped).
bp <- st_bbox(aff_p); bz <- st_bbox(aff_z %>% filter(!name %in% mountain))
frame <- st_bbox(c(xmin = bp[["xmin"]] - 3000, ymin = bz[["ymin"]] - 1500, xmax = bz[["xmax"]] + 1500, ymax = bp[["ymax"]] + 3000),
                 crs = st_crs(aff_p))

# Arrows from each closing school to its named receivers, stopped at the edge of the receiving marker so the
# head is not hidden under it. The map panel is about 564 px wide (0.47 of 1200).
xy <- st_coordinates(pts) %>% as_tibble() %>% mutate(name = pts$name)
r  <- 7 * as.numeric(frame["xmax"] - frame["xmin"]) / 564
arrows <- closure_plan %>% filter(level == "ES", action == "close", !is.na(receiving), receiving %in% pts$name) %>%
  left_join(xy, by = c("closing" = "name")) %>% rename(x0 = X, y0 = Y) %>%
  left_join(xy, by = c("receiving" = "name")) %>% rename(x1 = X, y1 = Y) %>%
  mutate(d = sqrt((x1 - x0)^2 + (y1 - y0)^2), x1 = x1 - (x1 - x0) / d * r, y1 = y1 - (y1 - y0) / d * r)

map <- ggplot() +
  geom_sf(data = bnd %>% filter(status == "no_change"), fill = NA, color = "#d3d2cc", linewidth = 0.25) +
  geom_sf(data = aff_z, aes(fill = status, alpha = status), color = NA) +
  # zone edges: a white casing with a thin dark line on top, so adjacent gray zones read as separate areas
  geom_sf(data = aff_z, fill = NA, color = "#ffffff", linewidth = 0.9) +
  geom_sf(data = aff_z, fill = NA, color = "#3d3c39", linewidth = 0.25) +
  geom_sf(data = dist, fill = NA, color = "#0b0b0b", linewidth = 0.3, linetype = "22") +
  geom_segment(data = arrows, aes(x = x0, y = y0, xend = x1, yend = y1), color = "#2b2a28", linewidth = 0.45,
               lineend = "round", linejoin = "mitre", arrow = arrow(length = unit(2, "mm"), angle = 22, type = "closed")) +
  geom_sf(data = aff_p, aes(fill = status, size = status), shape = 21, color = "#ffffff", stroke = 0.6) +
  scale_fill_manual(values = pt_fill, guide = "none", drop = FALSE) +
  scale_alpha_manual(values = alpha_status, guide = "none", drop = FALSE) +
  scale_size_manual(values = pt_size, guide = "none", drop = FALSE) +
  coord_sf(xlim = frame[c("xmin", "xmax")], ylim = frame[c("ymin", "ymax")], expand = FALSE, datum = NA) +
  theme_void() + theme(plot.background = element_rect(fill = "#f3f2ee", color = NA))

out <- file.path(dir_out, "psd_closures_preview.png")
agg_png(out, width = 1200, height = 630, res = 144, background = "#fcfcfb")
grid.newpage()
grid.rect(gp = gpar(fill = "#fcfcfb", col = NA))
pushViewport(viewport(x = 0.745, y = 0.5, width = 0.47, height = 0.9))
print(map, newpage = FALSE)
popViewport()
X <- 0.045
txt <- function(label, y, size, col = "#0b0b0b", face = "plain")
  grid.text(label, x = X, y = y, just = c("left", "top"), gp = gpar(fontsize = size, col = col, fontface = face, lineheight = 1.15))
txt("Poudre School District's\nclosure recommendation,\non the map", 0.89, 17, face = "bold")
txt("Attendance zones, schools, census trends,\nand the district's own stated reasons,\nwith the limits of the data.", 0.55, 9, col = "#52514e")
sw <- function(y, col, a, label) {
  grid.rect(x = X, y = y, width = unit(10, "bigpts"), height = unit(10, "bigpts"), just = c("left", "center"),
            gp = gpar(fill = adjustcolor(col, a + 0.25), col = NA))
  grid.text(label, x = unit(X, "npc") + unit(16, "bigpts"), y = y, just = "left", gp = gpar(fontsize = 8.5, col = "#0b0b0b"))
}
sw(0.36, col_status[["closing"]], alpha_status[["closing"]], "Recommended to close")
sw(0.30, col_status[["receiving"]], alpha_status[["receiving"]], "Named to receive students")
sw(0.24, col_status[["boundary_change"]], alpha_status[["boundary_change"]], "Boundary change")
grid.segments(x0 = X, x1 = unit(X, "npc") + unit(10, "bigpts"), y0 = 0.18, y1 = 0.18, gp = gpar(col = "#2b2a28", lwd = 1.2),
              arrow = arrow(length = unit(1.4, "mm"), type = "closed"))
grid.text("Closing school to named receiver", x = unit(X, "npc") + unit(16, "bigpts"), y = 0.18, just = "left", gp = gpar(fontsize = 8.5, col = "#0b0b0b"))
txt("Elementary schools only; middle school and consolidation changes\nare on the page. Independent analysis of public data;\nnot affiliated with PSD.", 0.115, 6.8, col = "#6f6e69")
invisible(dev.off())
cat("wrote", out, "\n")
