# PSD 2026 closure recommendation, on the map

Two interactive maps of Poudre School District's September 2026 recommendation to close nine schools and consolidate
two for the 2027-28 school year, with the district's own stated reasons, census and enrollment context, and the
limits of the data. The result is one self-contained web page, `output/psd_closures_map.html`.

This is a personal look at the questions I would want answered if I were making this decision. It is not an
argument for or against the recommendation. The committee and the board are weighing things this data cannot
show, such as programming at small schools, staffing, safety, and building condition. The project is independent
and not affiliated with Poudre School District.

## Rebuild the page
Requires R (4.6.1 used) and the packages recorded in `renv.lock`.

```r
install.packages("renv")
renv::restore()          # installs the recorded package versions
```

```sh
Rscript run_all.R        # about 20 seconds; writes output/psd_closures_map.html and the preview image
```

Everything needed is committed: raw inputs in `data/raw`, and the census blocks in `data/processed`. No download or
API key is needed. To re-download every raw input from its public source first, run
`REFRESH=true Rscript R/00a_fetch_raw.R`. A Census API key (`CENSUS_API_KEY`) is only needed if the cached census
blocks are deleted.

Every build first runs `R/00b_check_sources.R`, which checks each district quote, figure and page citation on the page
against the text of the district's PDFs and stops the build if anything no longer matches.

## Repository layout
| path | what |
|---|---|
| `run_all.R` | Runs the pipeline in order. |
| `R/00_setup.R` | Packages, paths, the closure plan table (`closure_plan`), and the school-name key used to join sources. |
| `R/00a_fetch_raw.R` | Downloads any missing raw input from its public source (`REFRESH=true` to re-download all). |
| `R/00b_check_sources.R` | Verifies district quotes and page citations against the PDFs. |
| `R/01_school_points.R` | PSD school points, NCES school ids, enrollment 2005-06 to 2024-25. |
| `R/02_boundaries.R` | Current attendance zones and district outline, with recommendation status. |
| `R/03a_census_fetch.R`, `R/03b_census_interpolate.R` | Census blocks 2000/2010/2020 and area-weighted counts per zone. |
| `R/04_utilization.R` | Working and full capacity, utilization and open seats. |
| `R/05_map.R`, `R/map_page_template.html` | The two-map web page. Publishing settings (`site_url`, `corrections_url`) are at the top of `05_map.R`. |
| `R/06_preview_image.R` | 1200 x 630 link-preview image. |
| `data/raw/` | Raw inputs as downloaded, with `SOURCES.md`. |
| `data/processed/` | Cleaned layers and cached census blocks. |
| `output/` | The page, its preview image, and the census and utilization tables behind it. |

## Outputs (`output/`)
| file | what |
|---|---|
| `psd_closures_map.html` | Self-contained web page (one file, ready to host): two Leaflet maps, a written guide under each, two tables, and a sources list. |
| `psd_closures_preview.png` | Link-preview image for social media. Host it next to the page. |
| `census_decennial_by_boundary_long.csv` / `_wide.csv` | Total and under-18 population for 2000, 2010 and 2020 inside every current attendance zone and the district. |
| `utilization_by_school.csv` | Full (RIC) and working (NSC) capacity, 2024-25 utilization and open seats per school, with the capacity source. |
| `utilization_summary.csv` | District and level totals before the closures; district totals after them (these do not depend on how closing zones are split). |

The page and these files deliberately contain no per-school estimates of how many students each receiving school gains,
because that depends on boundary splits the district has not published. `R/04_utilization.R` still computes an
even-split scenario for review; it is written to `output/scenario/`, which is not published.

## Map methodology (`output/psd_closures_map.html`)
The page states which figures are the district's and which are my calculations; this section mirrors it.

**Map 1, the district today.**
- Zones: PSD `Boundaries2022` (edited June/July 2026), one level at a time (elementary, middle, high).
- School points: PSD `Schools_PSD`, colored by level. The two 6-12 campuses (Timnath, Wellington) are green with
  an orange ring and are listed under both middle and high schools. Gray points are schools without an attendance
  zone, grouped by the school type in `Schools_PSD` (charter, option/choice, alternative high school, preschool).
  Every zone has a matching school point inside it (checked 2026-09-26).
- Census layers: percentage change in residents under 18 by elementary zone for 2000-2020, 2000-2010 and 2010-2020,
  shown one at a time. Every zone with a recorded starting population is shaded; gray is reserved for a zone with
  none (no such zone exists in the current data). Tooltips show the counts behind each percentage, because zones
  that were mostly undeveloped at the start (Bethke: 7 children in 2000; Zach: 22) show very large percentages.
- Zone pop-ups: total and under-18 population for 2000, 2010 and 2020 with 2000-2020 and 2010-2020 changes.
- District-wide figures on the page: under-18 +19% (35,625 to 42,519) and 18-and-over +46% (122,541 to 178,466)
  from 2000 to 2020; under-18 share 22.5% to 19.2%.

**Census method.** Block-level counts for Larimer County (2000 and 2010 Summary File 1, 2020 P.L. 94-171), pulled
through the Census Bureau API with tidycensus. Under-18 is total minus 18-and-over. Blocks are assigned to zones by
area-weighted interpolation (`sf::st_interpolate_aw`, extensive): each block's count is split among the zones it
touches in proportion to the share of its area in each, assuming people are spread evenly within a block. About
94% of populated blocks lie entirely inside one elementary zone and hold over 90% of residents (2000 and 2020
checked), so only edge blocks are split. Each census year uses its own block geometry. 2020 counts include the
Census Bureau's differential-privacy noise; zone totals are reliable, single blocks are not.

**Map 2, what the recommendation changes.**
- Opens on elementary changes only; middle school changes, the consolidating schools, and other schools are
  switched on from the layer menu. Consolidating schools are the largest markers, on the top layer.
- Zones shaded by status: closing (charcoal), receiving (blue), boundary change (yellow). Dashed lines join each
  closing school to each named receiver; they are not routes or final assignments.
- Pop-ups quote each school's "Summary Rationale" verbatim from the executive summary with a link to the page
  (`data/raw/psd_cpc/district_rationale_excerpts.csv`; all 12 excerpts, deferred-maintenance and savings figures
  checked against the cited pages on 2026-09-26). Beattie/Johnson and Irish/Putnam savings are reported as pairs.
- The page shows receiving schools as they are today and gives no estimate of how many students each gains,
  because that depends on boundary splits the district has not published (decision 2026-09-26; revisit after
  the Oct 6 packet). An even-split scenario remains in `output/utilization_by_school.csv` for review only.
  Harris, which takes only an optional cohort of multilingual learners from Irish, is left out of the receiving table.
- District-wide use of working capacity (73% to about 82%) is shown because it does not depend on the split,
  only on every student from a closing school moving to another PSD school.
- Capacity is the district's working capacity (NSC). The slides define it as 80% of capacity (p. 20); in the
  boundary layer the ratio is 0.80 elementary, 0.75 middle, 0.85 high (my calculation). Full capacity (RIC) is
  described on the slides only as the larger figure without space set aside for specialized programs.

**Enrollment in pop-ups.** 2010-11, 2015-16, 2019-20 and 2024-25 are PSD's counts from `Schools_PSD`. 2000-01 is
NCES Common Core of Data via the Urban Institute Education Data Portal, with preschool removed. With preschool removed,
the federal 2010-11 counts match PSD's within 3% for 40 of 41 schools. In 2000 PSD elementary schools served K-6 and
junior highs 7-9, so elementary figures also drop grade 6 to match today's K-5 schools; middle and high schools show
their 2000 grade span and are not directly comparable. The mountain schools changed NCES ids and are matched by
name. Wellington Middle-High's 2000-01 figure is its predecessor, Wellington Junior High (grades 7-9).

**Navigation.** Zoom buttons go to Poudre School District R-1 and to the Fort Collins city limits (Census
cartographic boundary file for places, 2024). Scroll-wheel zoom is on.

**Publishing.** Set `site_url` (the page's public address, needed for link previews) and optionally
`corrections_url` at the top of `R/05_map.R`, rebuild, and upload `psd_closures_map.html` together with
`psd_closures_preview.png` (the 1200 x 630 link-preview image from `R/06_preview_image.R`).

**Build.** `R/05_map.R` fills `R/map_page_template.html` with `htmltools::htmlTemplate`, saves it, and inlines every
script, stylesheet and image itself. pandoc's `--self-contained` is not used because it reflows text inside the
widget JSON and breaks the maps.

## Key findings
- **Enrollment fell at every closing school except Timnath** between 2015-16 and 2024-25. Blevins is down 39% and
  at 41% of the district's working capacity (NSC); Putnam is down 38% (44%); the three mountain schools have 22 to 36
  students each. Timnath Elementary grew 41% and is at 95% of working capacity. The executive summary gives facility
  condition and accessibility as the main reason for its closure (no elevator, about $6.5M in deferred maintenance),
  not decline.
- **Census under-18 counts inside the closing zones are flat to slightly down**, not collapsing: Beattie +1.7%,
  Irish -6.2%, Johnson -13.3%, Putnam -3.6% from 2010 to 2020. Over the same decade (2010-11 to 2020-21) enrollment
  fell 27% at Putnam and 22% at Johnson, faster than the child population, so choice, charters, or home schooling may
  explain part of the decline there. At Beattie and Irish, enrollment and child population moved roughly together
  (Beattie enrollment -4% vs children +2%; Irish -5% vs -6%). Under-18 counts include ages outside elementary school,
  so this points at a question rather than measuring an answer.
- **Children are a shrinking share of residents.** District-wide, residents under 18 grew 19% from 2000 to 2020 while
  adults grew 46%. The under-18 share fell in most zones (the typical zone went from about 26% to about 20%); it rose
  in newly built areas (Bethke, Zach, the Timnath 6-12 zone) and slightly in Laurel.
- **Receiving schools mostly declined too** (Bennett -30%, Linton -41%, Olander -32% since 2015-16), which is why they
  have room. Dunn is the exception at 98% of working capacity while being named as a Putnam receiver.
- **Open seats.** The district's 10,539 is working capacity minus *average projected* 2025-30 enrollment; with 2024-25
  enrollment the working-capacity gap is about 9,000 and the full-capacity gap about 17,200. The closing buildings hold
  about 3,500 working-capacity seats (about 40% of the gap), and district use of working capacity rises from 73% to
  about 82%. The largest remaining gaps are at Poudre High and several middle schools (see the capacity caveat below
  before quoting single schools).

## Caveats
- The announcement names two receivers for most closing schools but not how the boundary splits. The map draws a line
  to each receiver; redraw the splits if the October 6 board packet publishes them.
- Bacon's boundary change moves planning grid codes 1254 (from Bamford) and 1313-1314 (from Werner) (executive summary
  p. 21); the grid geometry is not public, so it is not drawn. The Centennial + PCA location is decided in early 2027.
- The executive summary prices operating savings and avoided deferred maintenance only. Implementation costs
  (receiving schools, the combined Centennial/PCA site, transportation, transition) are not yet estimated.
- Census counts are estimates (see "Census method"). Percent changes from a very small starting count, such as Bethke,
  Zach and Bacon in 2000, are shown on the map but say more about the small base than about trends.
- Mountain school zones (100 to 550 sq mi) include large unpopulated areas and small populations.
- PSD's `RIC`, `RICNC`, `FCI`, `NSC`, `FCA` fields on the boundary layer are carried through unchanged. The service does
  not define them; the slides define NSC and describe RIC only indirectly (p. 20).
- Capacities for schools the executive summary does not quote are derived as 2024-25 enrollment divided by the layer's
  RIC percentage. For some schools these run well above the older `Schools_PSD` capacity field: Eyestone 1,588 vs 700,
  Poudre HS 2,738 vs 1,883, Preston 1,420 vs 1,110, Boltz 1,148 vs 840. The layer may use a different enrollment count
  for those schools. Check before quoting any single school's figures.
- The executive summary appears to use a newer enrollment count than the 2024-25 figures here; its utilization for
  Beattie, Irish, Johnson and Putnam runs 3 to 5 points lower than mine.
- The page needs internet access for the Esri basemap.

## License and sources
Code is MIT licensed (`LICENSE`). Raw data are copies of public records and public data and remain under their
sources' terms; see `data/raw/SOURCES.md` for every source, URL and download date.
