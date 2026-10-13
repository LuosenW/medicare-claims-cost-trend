# 03_build_tables.R
# Builds the clean tables (members, member months, unified claims) and prints reconciliation checks.
# Run from the project root after 02_load_duckdb.R.

library(DBI)
library(duckdb)

con <- dbConnect(duckdb(), dbdir = file.path("db", "synpuf.duckdb"))

# Runs every statement in a .sql file, in order
run_sql_file <- function(con, path) {
  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
  stmts <- strsplit(txt, ";[ \t]*(\n|$)")[[1]]
  for (s in stmts) {
    code_only <- gsub("--[^\n]*", "", s)
    if (nchar(trimws(code_only)) == 0) next
    dbExecute(con, s)
  }
  message("Ran ", path)
}

run_sql_file(con, file.path("sql", "01_clean_members.sql"))
run_sql_file(con, file.path("sql", "02_claims.sql"))

# ---- Reconciliation: nothing should be lost or double counted between raw and clean ----

# A. Paid dollars, raw versus clean (should match to the cent)
recon_paid <- dbGetQuery(con, "
  SELECT 'Inpatient' AS source,
         (SELECT SUM(TRY_CAST(CLM_PMT_AMT AS DOUBLE)) FROM raw.inpatient)  AS raw_paid,
         (SELECT SUM(paid) FROM clean.claims_ip)                           AS clean_paid
  UNION ALL SELECT 'Outpatient',
         (SELECT SUM(TRY_CAST(CLM_PMT_AMT AS DOUBLE)) FROM raw.outpatient),
         (SELECT SUM(paid) FROM clean.claims_op)
  UNION ALL SELECT 'Pharmacy (total cost)',
         (SELECT SUM(TRY_CAST(TOT_RX_CST_AMT AS DOUBLE)) FROM raw.pde),
         (SELECT SUM(allowed) FROM clean.claims_rx)
")
recon_paid$difference <- recon_paid$clean_paid - recon_paid$raw_paid
print(recon_paid)

# B. Rows in versus claims out (inpatient segments explain any gap)
print(dbGetQuery(con, "
  SELECT 'Inpatient' AS source, (SELECT COUNT(*) FROM raw.inpatient) AS raw_rows,
         (SELECT COUNT(*) FROM clean.claims_ip) AS clean_claims,
         (SELECT COUNT(*) FROM clean.claims_ip WHERE n_segments > 1) AS multi_segment_claims
  UNION ALL SELECT 'Outpatient', (SELECT COUNT(*) FROM raw.outpatient), (SELECT COUNT(*) FROM clean.claims_op), NULL
  UNION ALL SELECT 'Professional', (SELECT COUNT(*) FROM raw.carrier), (SELECT COUNT(*) FROM clean.claims_prof), NULL
  UNION ALL SELECT 'Pharmacy', (SELECT COUNT(*) FROM raw.pde), (SELECT COUNT(*) FROM clean.claims_rx), NULL
"))

# C. Claims left out of scope (no valid date, or outside 2008 to 2010)
print(dbGetQuery(con, "
  SELECT service_category, COUNT(*) AS claims_out_of_scope, SUM(paid) AS paid_out_of_scope
  FROM clean.claims
  WHERE year IS NULL OR year NOT BETWEEN 2008 AND 2010
  GROUP BY service_category
"))

# D. Negative or zero paid claims (count them; decide how to treat them, then write it in the README)
print(dbGetQuery(con, "
  SELECT service_category,
         COUNT(*) FILTER (WHERE paid < 0)  AS negative_paid,
         COUNT(*) FILTER (WHERE paid = 0)  AS zero_paid,
         COUNT(*)                          AS claims
  FROM clean.claims_in_scope GROUP BY service_category ORDER BY service_category
"))

# D2. Pharmacy events where reported patient pay was larger than total drug cost (capped; see notes/decisions.md)
print(dbGetQuery(con, "
  SELECT YEAR(service_dt) AS year,
         COUNT(*) FILTER (WHERE patient_pay_capped)                                  AS events_capped,
         COUNT(*)                                                                    AS events,
         SUM(patient_pay_reported - member_cost)                                     AS patient_pay_removed,
         SUM(paid)                                                                   AS plan_paid_after_cap
  FROM clean.claims_rx GROUP BY 1 ORDER BY 1
"))

# E. Claims paid versus the annual totals CMS put on the beneficiary file.
#    In synthetic data these may not match; that is a finding to report, not a bug to hide.
print(dbGetQuery(con, "
  WITH claims AS (
    SELECT year, service_category, SUM(paid) AS claims_paid
    FROM clean.claims_in_scope GROUP BY ALL
  ),
  bene AS (
    SELECT year, SUM(bene_file_paid_ip) AS ip, SUM(bene_file_paid_op) AS op, SUM(bene_file_paid_car) AS car
    FROM clean.member_year GROUP BY year
  )
  SELECT b.year,
         b.ip  AS bene_file_ip,  (SELECT claims_paid FROM claims c WHERE c.year = b.year AND service_category = 'Inpatient')    AS claims_ip,
         b.op  AS bene_file_op,  (SELECT claims_paid FROM claims c WHERE c.year = b.year AND service_category = 'Outpatient')   AS claims_op,
         b.car AS bene_file_car, (SELECT claims_paid FROM claims c WHERE c.year = b.year AND service_category = 'Professional') AS claims_prof
  FROM bene b ORDER BY b.year
"))

# F. Exposure check
print(dbGetQuery(con, "SELECT * FROM clean.exposure ORDER BY year"))

dbDisconnect(con, shutdown = TRUE)
