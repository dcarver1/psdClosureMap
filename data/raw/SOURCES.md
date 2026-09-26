# Raw data sources

Every file here can be re-downloaded with `R/00a_fetch_raw.R` (`REFRESH=true` to overwrite). The copies committed
here are the ones the published page was built from, downloaded 2026-09-25 and 2026-09-26. A full re-download on
2026-09-26 reproduced every file: identical features and attributes for the map layers and API files, and
byte-identical PDFs.

## psd_arcgis/ -- Poudre School District ArcGIS Online (public)
REST root: https://services.arcgis.com/VBzywyYzcLrfMMGa/arcgis/rest/services/
Queried with `where=1=1&outFields=*&outSR=4326&f=geojson`.

| file | service / layer | data last edited | notes |
|---|---|---|---|
| Boundaries2022_layer0.geojson | Boundaries2022/0 (elementary) | 2026-07-08 | 29 zones. Fields RIC, RICNC, FCI, NSC, FCA, FCA_Remain are PSD facility and capacity metrics; RIC and NSC are utilization percentages (see `R/04_utilization.R`). |
| Boundaries2022_layer2.geojson | Boundaries2022/2 (middle) | 2026-06-12 | 9 zones, including the Timnath and Wellington 6-12 campuses |
| Boundaries2022_layer1.geojson | Boundaries2022/1 (high) | 2026-06-12 | 6 zones |
| Schools_PSD.geojson | Schools_PSD/0 | 2026-01-07 | 72 facilities including admin sites; school type; enrollment En_2005_06 to En_2024_25; older capacity fields |
| PSD_Boundary.geojson | PSD_Boundary/0 | n/a | district outline |

## nces/ -- National Center for Education Statistics
- `edge_geocode_publicsch_2425_psd.geojson`: EDGE public school geocodes 2024-25, LEAID 0803990 (52 schools), from
  https://nces.ed.gov/opengis/rest/services/K12_School_Locations/EDGE_GEOCODE_PUBLICSCH_2425/MapServer/0. Used for NCES school ids.
- Common Core of Data through the Urban Institute Education Data Portal (https://educationdata.urban.org):
  - `urban_ccd_school_directory_psd_2000.json`, `_2010.json`: `schools/ccd/directory/{year}/?leaid=0803990`
    (total enrollment including preschool, lowest and highest grade).
  - `urban_ccd_enrollment_pk_psd_2000.json`, `_2010.json`, `urban_ccd_enrollment_g6_psd_2000.json`:
    `schools/ccd/enrollment/{year}/grade-pk` and `grade-6` with `fips=8`, filtered to PSD (the API stores the
    district id as 803990).
  - Check: federal 2010-11 counts minus preschool match PSD's own 2010-11 counts within 3% for 40 of 41 schools.
  - In 2000 PSD elementary schools served K-6 and junior highs 7-9. The mountain schools changed NCES ids and are
    matched by name.

## psd_cpc/ -- PSD Comprehensive Planning Committee documents (September 25, 2026)
- `cpc_executive_summary_2026-09-25.pdf`: https://www.psdschools.org/fs/resource-manager/view/9c94a1cd-0de3-49b9-9ebb-f3f2128ec379
  (one cover sheet per recommended school: rationale, operating savings, deferred maintenance, transportation notes;
  Beattie/Johnson and Irish/Putnam savings are reported as pairs).
- `cpc_recommendation_slides_2026-09-25.pdf`: https://www.psdschools.org/fs/resource-manager/view/a62d419e-f10a-420d-a695-bd52a678df80
  ("Comprehensive Planning by the Numbers"). Cost charts on pp. 15-18 are images; p. 17 shows $8,408,145 small-school
  support funding across 33 schools. Open-seat count and capacity definitions on p. 20.
- `superintendent_announcement_2026-09-25.html` / `.txt`: https://www.psdschools.org/community/district-news-details/~board/poudre-school-district-news/post/psd-comprehensive-planning-committee-recommendation-released
  The `.txt` is the page's text, saved 2026-09-25; the `.html` was saved 2026-09-26.
- `executive_summary_pages/`, `slides_pages/`: text of each PDF page (written by `00a_fetch_raw.R` with pdftools or
  mutool). `R/00b_check_sources.R` uses them to verify every quote and page citation on the map page.
- `cpc_executive_summary_2026-09-25.txt`, `cpc_recommendation_slides_2026-09-25.txt`: whole-document text, kept for searching.
- `district_rationale_excerpts.csv`: hand-selected, verbatim excerpts of each school's "Summary Rationale" with PDF page
  numbers (original spelling kept; "[...]" marks omitted text), plus deferred maintenance and operating-savings
  figures with their pages. Checked by `R/00b_check_sources.R` on every build.

## Census (cached in data/processed/)
- `blocks_2000/2010/2020.gpkg`: decennial block counts for Larimer County from the Census Bureau API via tidycensus
  (`R/03a_census_fetch.R`). 2000 SF1 P001001 / P005001, 2010 SF1 P001001 / P010001, 2020 P.L. 94-171 P1_001N / P3_001N
  (total and 18 and over; under 18 = total minus 18 and over). A key is only needed to re-fetch them.
- `fort_collins_city_limits.gpkg`: Census cartographic boundary file, places, 2024 (`tigris::places("CO", year = 2024, cb = TRUE)`),
  used for the map's zoom button.
