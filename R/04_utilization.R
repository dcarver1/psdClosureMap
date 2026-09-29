# 04_utilization.R -- school utilization and empty seats, before and after the
# 2026-09-25 CPC recommendation (nine closures + Centennial/PCA consolidation).
#
# Capacity method (district): RIC = teaching spaces x students per space;
# NSC = RIC x a level factor (0.80 ES, 0.75 MS, 0.85 HS; see check below).
#
# Sources (all on disk):
#   data/raw/psd_arcgis/Boundaries2022_layer{0,2,1}.geojson
#       RIC / NSC fields are *utilization percentages* (enrollment / capacity, integer %),
#       not capacities -- they equal the "RIC Current" / "NSC Current" percents quoted in
#       the CPC executive summary for all 11 schools quoted there.
#   data/raw/psd_arcgis/Schools_PSD.geojson  En_2024_25 enrollment; legacy Capacity fields
#   data/raw/psd_cpc/cpc_executive_summary_2026-09-25.txt  RIC / NSC seat counts for the
#       recommended schools (transcribed in the `cpc` table below; txt_line is the line in that file).
#   data/processed/psd_schools.csv, psd_enrollment_long.csv  (from 01_school_points.R)
#   R/00_setup.R  closure_plan
#
# Capacity per school, in order of preference: the executive summary's seat counts; else 2024-25 enrollment
# divided by the boundary layer's RIC percentage; else the older Capacity_1 field in Schools_PSD (Harris,
# Traut and Kinard, which have no RIC percentage).
#
# Outputs (published): output/utilization_by_school.csv, output/utilization_summary.csv. Neither contains
#   per-school figures that depend on how closing zones are split.
# Outputs (review only, git-ignored): output/scenario/ -- an even-split scenario that divides each closing
#   school's students equally among its named receivers, plus a before/after chart.

source(file.path(if (basename(getwd()) == "R") ".." else ".", "R", "00_setup.R"))
suppressPackageStartupMessages({ library(ggplot2); library(ggrepel) })

# ---------------------------------------------------------------------------
# 1. Schools, status, 2024-25 enrollment
# ---------------------------------------------------------------------------
schools <- read_csv(file.path(dir_proc, "psd_schools.csv"), show_col_types = FALSE, col_types = cols(loc_code = col_character(), cde_code = col_character(), .default = col_guess()))
enr     <- read_csv(file.path(dir_proc, "psd_enrollment_long.csv"), show_col_types = FALSE) %>%
  filter(school_year == "2024-25") %>% select(name, enroll = enrollment)

pts <- st_read(file.path(dir_raw, "psd_arcgis", "Schools_PSD.geojson"), quiet = TRUE) %>%
  st_drop_geometry() %>%
  transmute(loc_code = LocCode, cap_legacy = Capacity, cap_legacy_main = Capacity_M,
            cap_legacy_mod = Capacity_1, modulars = Modulars, en_2024_25 = En_2024_25)

# Exclusions (capacity undefined or not a district-run school building)
excl <- tribble(
  ~name,                                   ~reason,
  "Ridgeview Classical",                   "charter",
  "Fort Collins Montessori",               "charter",
  "Liberty Common",                        "charter",
  "Liberty Common JR / SR",                "charter",
  "Mountain Sage Community",               "charter",
  "PSD Global Academy",                    "online/hybrid school; no RIC published; legacy capacity field is 0",
  "Polaris Expeditionary Learning School", "no RIC published; legacy capacity field (150) is stale (397 students)",
  "Fullana Elementary",                    "preschool site; no K-12 enrollment or capacity",
  "Eyestone South Elementary",             "second building of the Eyestone campus; the points layer repeats Eyestone's enrollment (524) so it would double count; the ES boundary layer has one Eyestone zone"
)

base <- schools %>%
  select(name, school_type, program, status, loc_code, key) %>%
  distinct(name, .keep_all = TRUE) %>%
  filter(!name %in% excl$name) %>%
  left_join(enr, by = "name") %>%
  left_join(pts %>% distinct(loc_code, .keep_all = TRUE) %>% mutate(loc_code = as.character(loc_code)),
            by = c("loc_code")) %>%
  mutate(level = recode(school_type, "MS / HS" = "MS/HS"))
stopifnot(!any(is.na(base$enroll)))

# ---------------------------------------------------------------------------
# 2. Boundary layers: RIC / NSC utilization percentages
# ---------------------------------------------------------------------------
read_layer <- function(file, suffix) {
  st_read(file.path(dir_raw, "psd_arcgis", file), quiet = TRUE) %>% st_drop_geometry() %>%
    transmute(School, key = school_key(ifelse(str_detect(School, "Middle-High"), School,
                                              paste(School, suffix))),
              ric_pct = as.numeric(RIC), nsc_pct = as.numeric(NSC),
              ricnc_pct = as.numeric(RICNC), fci = as.numeric(FCI), fca = as.numeric(FCA))
}
lyr <- bind_rows(read_layer("Boundaries2022_layer0.geojson", "Elementary"),
                 read_layer("Boundaries2022_layer2.geojson", "Middle"),
                 read_layer("Boundaries2022_layer1.geojson", "HS")) %>%
  distinct(key, .keep_all = TRUE)   # Timnath / Wellington M-HS appear in both MS and HS layers

# ---------------------------------------------------------------------------
# 3. District-quoted seat counts (cpc_executive_summary_2026-09-25.txt)
#    "RIC Current: enrolled/RIC = %", "NSC Current: enrolled/NSC = %"
# ---------------------------------------------------------------------------
cpc <- tribble(
  ~name,                       ~enroll_cpc, ~ric_cap_cpc, ~nsc_cap_cpc, ~ric_pct_cpc, ~nsc_pct_cpc, ~txt_line,
  "Beattie Elementary",         231, 500,  400,  46,    58,    126,
  "Irish Elementary",           272, 669,  535,  41,    51,    417,
  "Johnson Elementary",         281, 625,  500,  45,    56,    687,
  "Stove Prairie Elementary",    21, 100,   80,  21,    26,    980,
  "Livermore Elementary",        37, 100,   80,  37,    46,    986,
  "Red Feather Elementary",      20, 100,   80,  20,    25,    992,
  "Putnam Elementary",          174, 575,  460,  30,    38,   1289,
  "Timnath Elementary",         424, 560,  448,  76,    95,   1568,
  "Blevins Middle",             365, 1170, 878,  31,    42,   1868,
  "Poudre Community Academy",   105, 313,  250,  33.55, 39.47, 2181,
  "Centennial HS",               87, 391,  332,  22.25, 26.20, 2185
)

# NSC / RIC factor by level. ES, MS and HS are checked against the layer percentages below; the MS/HS and
# Option values are assumptions (the district's stated 80%) for the few schools without a layer percentage.
nsc_factor <- c(ES = 0.80, MS = 0.75, HS = 0.85, `MS/HS` = 0.80, Option = 0.80)

tab <- base %>%
  left_join(lyr %>% select(-School), by = "key") %>%
  left_join(cpc, by = "name") %>%
  mutate(
    capacity_source = case_when(
      !is.na(ric_cap_cpc) ~ "cpc_exec_summary",
      !is.na(ric_pct)     ~ "derived: En_2024_25 / Boundaries2022 RIC%",
      TRUE                ~ "legacy Schools_PSD Capacity_1 (not RIC)"),
    ric_cap = case_when(
      !is.na(ric_cap_cpc) ~ as.numeric(ric_cap_cpc),
      !is.na(ric_pct)     ~ round(enroll / (ric_pct / 100)),
      TRUE                ~ as.numeric(cap_legacy_mod)),
    nsc_cap = case_when(
      !is.na(nsc_cap_cpc) ~ as.numeric(nsc_cap_cpc),
      TRUE                ~ round(ric_cap * nsc_factor[level]))
  )

# Check: implied NSC/RIC ratio from the layer vs the level factor
chk <- tab %>% filter(!is.na(ric_pct)) %>%
  mutate(ratio = ric_pct / nsc_pct, fac = nsc_factor[level], dev = ratio - fac)
cat("\nNSC/RIC factor check (layer ratio minus assumed factor), by level:\n")
print(chk %>% group_by(level) %>% summarise(n = n(), min_ratio = min(ratio), max_ratio = max(ratio),
                                            max_abs_dev = max(abs(dev))), width = 120)

util <- function(e, cap) ifelse(is.na(cap) | cap == 0, NA_real_, e / cap)
before <- tab %>%
  mutate(util_ric = util(enroll, ric_cap), util_nsc = util(enroll, nsc_cap),
         empty_ric = ric_cap - enroll, empty_nsc = nsc_cap - enroll)

# ---------------------------------------------------------------------------
# 4. After the recommendation
#    - nine closures: capacity removed, 2024-25 enrollment split equally among the
#      named receivers (Harris is an *optional* cohort for Irish -> weight 0)
#    - consolidation: two cases, campus removed = Centennial (A) or PCA (B)
# ---------------------------------------------------------------------------
moves <- closure_plan %>% filter(action == "close") %>%
  mutate(w = ifelse(receiving == "Harris Elementary", 0, 1)) %>%
  group_by(closing) %>% mutate(share = w / sum(w)) %>% ungroup() %>%
  left_join(enr, by = c("closing" = "name")) %>%
  mutate(moved = enroll * share)
cat("\nReassignment (2024-25 enrollment, equal split):\n"); print(moves %>% select(closing, receiving, share, moved), n = 30)
gains <- moves %>% group_by(name = receiving) %>% summarise(gained = sum(moved), from = paste(unique(closing), collapse = "; "))

apply_plan <- function(df, consol_remove = c("none", "Centennial HS", "Poudre Community Academy"), shrink = 1) {
  consol_remove <- match.arg(consol_remove)
  consol_total  <- sum(df$enroll[df$name %in% consolidating])
  keep_campus   <- setdiff(consolidating, consol_remove)
  df %>%
    left_join(gains, by = "name") %>%
    mutate(gained = replace_na(gained, 0),
           removed = name %in% closing_schools | name == consol_remove,
           enroll_after  = case_when(removed ~ 0,
                                     consol_remove != "none" & name %in% keep_campus ~ consol_total,
                                     TRUE ~ enroll + gained),
           enroll_after  = enroll_after * shrink,
           ric_cap_after = ifelse(removed, 0, ric_cap),
           nsc_cap_after = ifelse(removed, 0, nsc_cap),
           util_ric_after = util(enroll_after, ric_cap_after),
           util_nsc_after = util(enroll_after, nsc_cap_after),
           empty_ric_after = ric_cap_after - enroll_after,
           empty_nsc_after = nsc_cap_after - enroll_after)
}

summarise_scen <- function(df, scenario, enroll_col, ric_col, nsc_col) {
  f <- function(d, lvl) tibble(
    scenario = scenario, level = lvl, n_schools = sum(d[[ric_col]] > 0),
    enrollment = sum(d[[enroll_col]]), ric = sum(d[[ric_col]]), nsc = sum(d[[nsc_col]]),
    empty_ric_net = sum(d[[ric_col]] - d[[enroll_col]]),
    empty_nsc_net = sum(d[[nsc_col]] - d[[enroll_col]]),
    empty_ric_gross = sum(pmax(d[[ric_col]] - d[[enroll_col]], 0)[d[[ric_col]] > 0]),
    empty_nsc_gross = sum(pmax(d[[nsc_col]] - d[[enroll_col]], 0)[d[[nsc_col]] > 0]),
    util_ric = enrollment / ric, util_nsc = enrollment / nsc,
    n_under70_nsc = sum(d[[nsc_col]] > 0 & d[[enroll_col]] / d[[nsc_col]] < 0.70),
    n_over95_nsc  = sum(d[[nsc_col]] > 0 & d[[enroll_col]] / d[[nsc_col]] > 0.95),
    n_over100_ric = sum(d[[ric_col]] > 0 & d[[enroll_col]] / d[[ric_col]] > 1.00))
  bind_rows(f(df, "District (all included)"),
            f(df %>% filter(capacity_source != "legacy Schools_PSD Capacity_1 (not RIC)"), "District (district-method capacities only)"),
            map_dfr(c("ES", "MS", "HS", "MS/HS", "Option"), ~ f(df %>% filter(level == .x), .x)))
}

# Scenarios (review only). The "_2030" rows apply a flat 7.5% enrollment decline to every school as a
# sensitivity check; it is a round assumption, not a district projection.
scen <- list(
  before                          = before %>% mutate(enroll_after = enroll, ric_cap_after = ric_cap, nsc_cap_after = nsc_cap),
  after_closures_only             = apply_plan(before, "none"),
  after_A_consol_remove_Centennial = apply_plan(before, "Centennial HS"),
  after_B_consol_remove_PCA        = apply_plan(before, "Poudre Community Academy"),
  before_2030_minus7.5pct          = before %>% mutate(enroll_after = enroll * 0.925, ric_cap_after = ric_cap, nsc_cap_after = nsc_cap),
  after_closures_only_2030         = apply_plan(before, "none", shrink = 0.925),
  after_A_2030                     = apply_plan(before, "Centennial HS", shrink = 0.925),
  after_B_2030                     = apply_plan(before, "Poudre Community Academy", shrink = 0.925)
)
summary_tbl <- imap_dfr(scen, ~ summarise_scen(.x, .y, "enroll_after", "ric_cap_after", "nsc_cap_after")) %>%
  mutate(across(c(util_ric, util_nsc), ~ round(.x, 4)))

# ---------------------------------------------------------------------------
# 5. By-school output (before + after closures-only; consolidation cases as extra cols)
# ---------------------------------------------------------------------------
afterA <- scen$after_A_consol_remove_Centennial %>% select(name, util_nsc_after_A = util_nsc_after, util_ric_after_A = util_ric_after)
afterB <- scen$after_B_consol_remove_PCA        %>% select(name, util_nsc_after_B = util_nsc_after, util_ric_after_B = util_ric_after)
after2030 <- scen$after_closures_only_2030 %>% select(name, util_nsc_after_2030 = util_nsc_after, util_ric_after_2030 = util_ric_after)

by_school <- scen$after_closures_only %>%
  left_join(afterA, by = "name") %>% left_join(afterB, by = "name") %>% left_join(after2030, by = "name") %>%
  mutate(flag_after = case_when(
    removed ~ "closed",
    util_ric_after > 1.00 ~ "over 100% RIC",
    util_nsc_after > 0.95 ~ "over 95% NSC",
    util_nsc_after < 0.70 ~ "under 70% NSC",
    TRUE ~ "")) %>%
  select(name, level, program, status, enroll_2024_25 = enroll,
         ric_cap, nsc_cap, capacity_source, util_ric, util_nsc, empty_ric, empty_nsc,
         layer_ric_pct = ric_pct, layer_nsc_pct = nsc_pct, layer_ricnc_pct = ricnc_pct, layer_fci = fci,
         cpc_enroll = enroll_cpc, cpc_ric_cap = ric_cap_cpc, cpc_nsc_cap = nsc_cap_cpc,
         legacy_capacity = cap_legacy, legacy_capacity_main = cap_legacy_main, legacy_capacity_with_mod = cap_legacy_mod,
         received_from = from, gained_students = gained,
         enroll_after, ric_cap_after, nsc_cap_after, util_ric_after, util_nsc_after, empty_ric_after, empty_nsc_after,
         util_ric_after_A, util_nsc_after_A, util_ric_after_B, util_nsc_after_B,
         util_ric_after_2030, util_nsc_after_2030, flag_after) %>%
  mutate(across(where(is.double) & starts_with("util"), ~ round(.x, 4)),
         across(c(gained_students, enroll_after, empty_ric_after, empty_nsc_after), ~ round(.x, 1))) %>%
  arrange(level, desc(util_nsc))

# Public outputs match the map page: no per-school figures that depend on how closing zones are split
# (the district has not published the splits). The full even-split scenario goes to output/scenario/,
# which is git-ignored, for review only.
dir_scen <- file.path(dir_out, "scenario"); dir.create(dir_scen, showWarnings = FALSE)
write_csv(by_school, file.path(dir_scen, "utilization_by_school_even_split.csv"), na = "")
write_csv(summary_tbl, file.path(dir_scen, "utilization_summary_even_split.csv"), na = "")
split_cols <- c("received_from", "gained_students", "enroll_after", "ric_cap_after", "nsc_cap_after", "util_ric_after",
                "util_nsc_after", "empty_ric_after", "empty_nsc_after", "util_ric_after_A", "util_nsc_after_A",
                "util_ric_after_B", "util_nsc_after_B", "util_ric_after_2030", "util_nsc_after_2030", "flag_after")
write_csv(by_school %>% select(-any_of(split_cols)), file.path(dir_out, "utilization_by_school.csv"), na = "")
# District-level totals do not depend on the split (every student from a closing school moves to another PSD
# school); counts of schools above or below thresholds after the closures do, so they are dropped here.
write_csv(summary_tbl %>% filter(scenario == "before" | str_detect(level, "^District")) %>%
            mutate(across(c(starts_with("n_under"), starts_with("n_over"), ends_with("_gross")), ~ ifelse(scenario == "before", .x, NA))),
          file.path(dir_out, "utilization_summary.csv"), na = "")

# ---------------------------------------------------------------------------
# 6. Console report
# ---------------------------------------------------------------------------
options(width = 200)
cat("\n== Excluded ==\n"); print(excl, n = 20)
cat("\n== District summary ==\n")
print(summary_tbl %>% filter(str_detect(level, "District")) %>%
        select(scenario, level, n_schools, enrollment, ric, nsc, empty_ric_net, empty_nsc_net, empty_nsc_gross, util_ric, util_nsc, n_under70_nsc, n_over95_nsc, n_over100_ric), n = 30)
cat("\n== By level, before and after (closures only) ==\n")
print(summary_tbl %>% filter(!str_detect(level, "District"), scenario %in% c("before", "after_closures_only")) %>%
        select(scenario, level, n_schools, enrollment, ric, nsc, empty_ric_net, empty_nsc_net, util_ric, util_nsc, n_under70_nsc), n = 30)

cat("\n== Sanity: district-quoted vs this script ==\n")
print(by_school %>% filter(!is.na(cpc_ric_cap)) %>%
        transmute(name, enroll_2024_25, cpc_enroll, ric_cap, nsc_cap,
                  util_ric_2425 = round(100 * util_ric), cpc_ric_pct = round(cpc_enroll / cpc_ric_cap * 100), layer_ric_pct,
                  util_nsc_2425 = round(100 * util_nsc), cpc_nsc_pct = round(cpc_enroll / cpc_nsc_cap * 100), layer_nsc_pct,
                  derived_ric_if_no_cpc = round(enroll_2024_25 / (layer_ric_pct / 100))), n = 20)

cat("\n== Receivers after (closures only; 2024-25 enrollment; and -7.5%) ==\n")
print(by_school %>% filter(status == "receiving") %>%
        transmute(name, enroll_2024_25, gained_students, enroll_after, ric_cap, nsc_cap,
                  util_nsc_before = util_nsc, util_nsc_after, util_ric_after, util_nsc_after_2030, flag_after) %>%
        arrange(desc(util_nsc_after)), n = 20)

cat("\n== Consolidation cases ==\n")
print(by_school %>% filter(name %in% consolidating) %>%
        select(name, enroll_2024_25, ric_cap, nsc_cap, util_nsc, util_nsc_after_A, util_nsc_after_B, util_ric_after_A, util_ric_after_B))

cat("\n== Under 70% NSC before ==\n")
print(by_school %>% filter(util_nsc < 0.70) %>% select(name, level, status, enroll_2024_25, nsc_cap, util_nsc, empty_nsc) %>% arrange(util_nsc), n = 40)
cat("\n== Under 70% NSC after (closures only), largest remaining empty-seat blocks first ==\n")
print(by_school %>% filter(flag_after != "closed", util_nsc_after < 0.70) %>%
        select(name, level, status, enroll_after, nsc_cap, util_nsc_after, empty_nsc_after, util_nsc_after_2030) %>%
        arrange(desc(empty_nsc_after)), n = 40)
cat("\n== Largest remaining empty-seat blocks after plan (NSC), any utilization ==\n")
print(by_school %>% filter(flag_after != "closed") %>% select(name, level, enroll_after, nsc_cap, util_nsc_after, empty_nsc_after) %>%
        arrange(desc(empty_nsc_after)) %>% head(12))

# ---------------------------------------------------------------------------
# 7. Chart: NSC utilization per school, before vs after (dumbbell), 70% / 95% guides
# ---------------------------------------------------------------------------
col_before <- "#9cc0ea"; col_after <- "#2a78d6"; col_close <- "#52514e"
ink <- "#0b0b0b"; ink2 <- "#52514e"; surface <- "#fcfcfb"; grid_col <- "#e6e5e1"

plot_df <- by_school %>%
  mutate(closing = flag_after == "closed",
         label = ifelse(name %in% consolidating, paste0(name, " (consolidating)"), name),
         label = str_replace(label, " Elementary", ""),
         level_f = factor(level, levels = c("ES", "MS", "MS/HS", "HS", "Option"),
                          labels = c("Elementary", "Middle", "Middle-High", "High", "Option"))) %>%
  arrange(level_f, util_nsc) %>%
  mutate(label = factor(label, levels = unique(label)),
         after_pt = ifelse(closing, NA, util_nsc_after))

pg <- ggplot(plot_df, aes(y = label)) +
  geom_vline(xintercept = c(0.70, 0.95), colour = ink2, linetype = "22", linewidth = 0.4) +
  geom_point(aes(x = util_nsc, colour = "Before (2024-25)", shape = closing), size = 2.6, fill = surface) +
  # segment layer after the full-data point layer: a discrete scale trains levels in layer order and drops unused ones
  geom_segment(data = filter(plot_df, !closing & abs(util_nsc_after - util_nsc) > 0.001),
               aes(x = util_nsc, xend = util_nsc_after, yend = label), colour = col_after, linewidth = 0.8) +
  geom_point(aes(x = after_pt, colour = "After plan"), size = 2.6, na.rm = TRUE) +
  geom_text(data = filter(plot_df, closing), aes(x = util_nsc, label = "closes"),
            hjust = -0.35, size = 2.6, colour = ink2) +
  annotate("text", x = 0.70, y = Inf, label = "70%", vjust = 1.4, hjust = 1.1, size = 2.8, colour = ink2) +
  annotate("text", x = 0.95, y = Inf, label = "95%", vjust = 1.4, hjust = -0.1, size = 2.8, colour = ink2) +
  facet_grid(level_f ~ ., scales = "free_y", space = "free_y", switch = "y") +
  scale_colour_manual(NULL, values = c("Before (2024-25)" = col_before, "After plan" = col_after),
                      breaks = c("Before (2024-25)", "After plan")) +
  scale_shape_manual(NULL, values = c(`FALSE` = 16, `TRUE` = 4), labels = c("", "Closing school"), guide = "none") +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1), breaks = seq(0.2, 1.2, 0.2),
                     limits = c(0.15, 1.30), expand = expansion(0)) +
  labs(title = "PSD school use of working capacity (NSC), before and after the CPC plan",
       subtitle = paste0("Use = 2024-25 enrollment / NSC. After: nine closures removed, their students split equally among named receivers (illustrative only).\n",
                         "Guide lines mark 70% and 95%. X marks = schools recommended to close (their students move right along the blue segments)."),
       x = "Use of working capacity (NSC)", y = NULL,
       caption = paste0("Capacity: CPC executive summary seat counts (11 schools) or Boundaries2022 RIC%/NSC% fields x 2024-25 enrollment;\n",
                        "Harris, Kinard and Traut use the legacy Schools_PSD capacity field (no RIC published).\n",
                        "Centennial and PCA are shown at their current campuses; the consolidation outcome depends on which campus is kept.")) +
  theme_minimal(base_size = 11) +
  theme(plot.background = element_rect(fill = surface, colour = NA), panel.background = element_rect(fill = surface, colour = NA),
        panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
        panel.grid.major.x = element_line(colour = grid_col, linewidth = 0.3),
        strip.placement = "outside", strip.text.y.left = element_text(angle = 0, face = "bold", colour = ink, hjust = 1),
        axis.text.y = element_text(colour = ink, size = 8.5), axis.text.x = element_text(colour = ink2),
        legend.position = "top", legend.justification = "left", text = element_text(colour = ink),
        plot.title = element_text(face = "bold", size = 13), plot.subtitle = element_text(colour = ink2, size = 9),
        plot.caption = element_text(colour = ink2, size = 7.5, hjust = 0), plot.title.position = "plot",
        panel.spacing.y = unit(8, "pt"))
ggsave(file.path(dir_scen, "utilization_before_after_even_split.png"), pg, width = 10, height = 12.5, dpi = 170, bg = surface, device = ragg::agg_png)
cat("\nWrote output/utilization_by_school.csv, output/utilization_summary.csv, and the review-only files in output/scenario/\n")
