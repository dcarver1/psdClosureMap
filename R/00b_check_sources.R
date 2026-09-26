# 00b_check_sources.R -- verify that every district quote and page citation on the map page matches its source.
# Reads the per-page text written by 00a_fetch_raw.R. Stops with a list of failures if anything does not match,
# so a changed document or a typo in the excerpts cannot reach the published page unnoticed.
source(file.path(if (basename(getwd()) == "R") "." else "R", "00_setup.R"))

norm <- function(x) str_squish(str_replace_all(paste(x, collapse = " "), "[‘’]", "'"))
page_txt <- function(doc, p) norm(readLines(file.path(dir_raw, "psd_cpc", doc, sprintf("page_%02d.txt", as.integer(p))), warn = FALSE))
exec  <- function(p) page_txt("executive_summary_pages", p)
slide <- function(p) page_txt("slides_pages", p)
ann   <- norm(readLines(file.path(dir_raw, "psd_cpc", "superintendent_announcement_2026-09-25.txt"), warn = FALSE))

checks <- list()
chk <- function(what, ok) checks[[length(checks) + 1]] <<- tibble(check = what, ok = isTRUE(ok))

# 1. Rationale excerpts (verbatim; "[...]" marks omitted text) and the figures cited beside them
rat <- read_csv(file.path(dir_raw, "psd_cpc", "district_rationale_excerpts.csv"), show_col_types = FALSE)
for (i in seq_len(nrow(rat))) {
  r <- rat[i, ]
  parts <- vapply(str_split(r$rationale_excerpt, fixed("[...]"))[[1]], norm, "")
  chk(sprintf("%s: quote on p. %d", r$school, r$rationale_page), all(vapply(parts, function(x) str_detect(exec(r$rationale_page), fixed(x)), TRUE)))
  if (!is.na(r$deferred_maintenance_usd)) {
    v <- r$deferred_maintenance_usd; pg <- exec(r$deferred_maintenance_page)
    chk(sprintf("%s: deferred maintenance on p. %d", r$school, r$deferred_maintenance_page),
        str_detect(pg, fixed(format(v, big.mark = ",", scientific = FALSE))) || str_detect(pg, fixed(sprintf("$%.1f million", v / 1e6))))
  }
  if (!is.na(r$operating_savings)) {
    amt <- str_extract(r$operating_savings, "\\$[0-9.,]+M?")
    key <- if (str_ends(amt, "M")) paste0(str_remove(amt, "M$"), " million") else amt
    chk(sprintf("%s: savings on p. %d", r$school, r$savings_page), str_detect(exec(r$savings_page), fixed(key)))
  }
}

# 2. Other facts the page cites by page
chk("Slides p. 20: 10,539 open seats", str_detect(slide(20), fixed("10,539")))
chk("Slides p. 20: NSC is 80% of the capacity", str_detect(slide(20), fixed("NSC is 80% of the capacity")))
chk("Slides p. 20: RIC wording quoted on the page", str_detect(slide(20), fixed("would be higher (RIC) if")))
chk("Executive summary p. 19: Putnam drive miles", str_detect(exec(19), fixed("Putnam is 4.3 drive miles from Tavelli and 1.3 drive miles from Dunn")))
chk("Executive summary p. 21: Bacon grid codes", str_detect(exec(21), fixed("Reassign Grid Code 1254 from Bamford to Bacon")))
chk("Announcement: seventeen months", str_detect(ann, fixed("seventeen months")))
chk("Announcement: Board meeting October 13", str_detect(ann, fixed("October 13")))
chk("Announcement: vote October 27", str_detect(ann, fixed("October 27")))
chk("Announcement: Harris cohort", str_detect(ann, fixed("Harris Bilingual Immersion")))
chk("Announcement: listening sessions Oct 12-19", str_detect(ann, fixed("October 12-19")))

res <- bind_rows(checks)
cat(sprintf("source checks: %d of %d passed\n", sum(res$ok), nrow(res)))
if (!all(res$ok)) { print(res %>% filter(!ok), n = 50); stop("Source checks failed; fix the excerpts or citations before rebuilding the page.") }
