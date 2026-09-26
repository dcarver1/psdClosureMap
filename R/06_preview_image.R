# 06_preview_image.R -- 1200 x 630 link-preview image for Facebook / LinkedIn (og:image)
# Output: output/psd_closures_preview.png. Upload it next to psd_closures_map.html on the website.
source(file.path(if (basename(getwd()) == "R") "." else "R", "00_setup.R"))
suppressPackageStartupMessages({ library(ggplot2); library(grid); library(ragg) })

bnd <- st_read(file.path(dir_proc, "boundaries_current.gpkg"), quiet = TRUE) %>% st_transform(crs_utm) %>% filter(level == "ES")
pts <- st_read(file.path(dir_proc, "psd_schools.gpkg"), quiet = TRUE) %>% st_transform(crs_utm)

col_status <- c(closing = "#52514e", receiving = "#2a78d6", boundary_change = "#eda100", no_change = "#fcfcfb")
alpha_status <- c(closing = 0.55, receiving = 0.30, boundary_change = 0.40, no_change = 0)
mountain <- c("Livermore Elementary", "Red Feather Elementary", "Stove Prairie Elementary")

# Frame the Fort Collins city limits (plus a margin); the mountain zones are mentioned in the text instead.
city <- st_read(file.path(dir_proc, "fort_collins_city_limits.gpkg"), quiet = TRUE) %>% st_transform(crs_utm)
frame <- st_bbox(city) + c(-2500, -1500, 2500, 1500)
aff_pts <- pts %>% filter(status %in% c("closing", "receiving", "boundary_change"), !name %in% mountain)

map <- ggplot() +
  geom_sf(data = bnd, aes(fill = status, alpha = status), color = "#9c9b95", linewidth = 0.25) +
  geom_sf(data = aff_pts, aes(fill = status), shape = 21, color = "#ffffff", size = 2.6, stroke = 0.6) +
  scale_fill_manual(values = col_status, guide = "none") +
  scale_alpha_manual(values = alpha_status, guide = "none") +
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
sw(0.33, col_status[["closing"]], alpha_status[["closing"]], "Recommended to close")
sw(0.27, col_status[["receiving"]], alpha_status[["receiving"]], "Named to receive students")
sw(0.21, col_status[["boundary_change"]], alpha_status[["boundary_change"]], "Boundary change")
txt("Fort Collins area shown. Three mountain schools are\nalso recommended to close. Independent analysis of\npublic data; not affiliated with PSD.", 0.14, 6.8, col = "#6f6e69")
invisible(dev.off())
cat("wrote", out, "\n")
