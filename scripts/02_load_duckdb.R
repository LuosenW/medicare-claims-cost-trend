# 02_load_duckdb.R
# Loads the raw DE-SynPUF CSVs into a DuckDB database file and runs data validation checks.
# Raw tables are loaded as text on purpose: diagnosis and procedure codes have leading zeros
# (for example "0389") that would be lost if read as numbers. Typing and cleaning come in step 3.

# install.packages(c("DBI", "duckdb"))   # run once
library(DBI)
library(duckdb)

raw_csv <- file.path("data", "raw", "csv")
dir.create("db", showWarnings = FALSE)
con <- dbConnect(duckdb(), dbdir = file.path("db", "synpuf.duckdb"))

sample <- 2   # must match 01_get_data.R
find_csv <- function(pattern) {
  f <- list.files(raw_csv, pattern = paste0(pattern, ".*Sample_", sample, "[AB]?\\.csv$"), full.names = TRUE, ignore.case = TRUE)
  if (length(f) == 0) stop("No CSV matching ", pattern)
  normalizePath(f, winslash = "/")
}
sql_list <- function(paths) paste0("[", paste0("'", paths, "'", collapse = ", "), "]")

dbExecute(con, "CREATE SCHEMA IF NOT EXISTS raw")

# Beneficiary summary: one file per year, stacked with a year column
bene_sql <- paste(
  sapply(2008:2010, function(y) {
    sprintf("SELECT %d AS file_year, * FROM read_csv(%s, all_varchar = true, header = true)",
            y, sql_list(find_csv(sprintf("%d_Beneficiary_Summary_File", y))))
  }),
  collapse = " UNION ALL BY NAME "
)
dbExecute(con, paste("CREATE OR REPLACE TABLE raw.beneficiary AS", bene_sql))

load_claims <- function(table, pattern) {
  dbExecute(con, sprintf(
    "CREATE OR REPLACE TABLE raw.%s AS SELECT * FROM read_csv(%s, all_varchar = true, header = true, union_by_name = true)",
    table, sql_list(find_csv(pattern))))
}
load_claims("inpatient",  "Inpatient_Claims")
load_claims("outpatient", "Outpatient_Claims")
load_claims("carrier",    "Carrier_Claims")   # A and B files together
load_claims("pde",        "Prescription_Drug_Events")

# ---- Validation checks (save this output; it goes in your README) ----

# 1. Row counts and distinct beneficiaries per table
counts <- dbGetQuery(con, "
  SELECT 'beneficiary' AS tbl, COUNT(*) AS n_rows, COUNT(DISTINCT DESYNPUF_ID) AS n_benes FROM raw.beneficiary
  UNION ALL SELECT 'inpatient',  COUNT(*), COUNT(DISTINCT DESYNPUF_ID) FROM raw.inpatient
  UNION ALL SELECT 'outpatient', COUNT(*), COUNT(DISTINCT DESYNPUF_ID) FROM raw.outpatient
  UNION ALL SELECT 'carrier',    COUNT(*), COUNT(DISTINCT DESYNPUF_ID) FROM raw.carrier
  UNION ALL SELECT 'pde',        COUNT(*), COUNT(DISTINCT DESYNPUF_ID) FROM raw.pde
")
print(counts)

# 2. Beneficiaries per file year (should be roughly 1/20 of the CMS published totals)
print(dbGetQuery(con, "SELECT file_year, COUNT(*) AS benes FROM raw.beneficiary GROUP BY 1 ORDER BY 1"))

# 3. Claims by service year (expect 2010 to be lower; CMS notes deaths and disclosure treatment)
print(dbGetQuery(con, "
  SELECT 'inpatient' AS tbl, LEFT(CLM_FROM_DT, 4) AS yr, COUNT(*) AS n FROM raw.inpatient GROUP BY ALL
  UNION ALL SELECT 'outpatient', LEFT(CLM_FROM_DT, 4), COUNT(*) FROM raw.outpatient GROUP BY ALL
  UNION ALL SELECT 'carrier',    LEFT(CLM_FROM_DT, 4), COUNT(*) FROM raw.carrier GROUP BY ALL
  UNION ALL SELECT 'pde',        LEFT(SRVC_DT, 4),     COUNT(*) FROM raw.pde GROUP BY ALL
  ORDER BY 1, 2
"))

# 4. Orphan claims: claim rows whose beneficiary is not in the beneficiary file (should be 0)
print(dbGetQuery(con, "
  SELECT 'inpatient' AS tbl, COUNT(*) AS orphans FROM raw.inpatient c
    WHERE NOT EXISTS (SELECT 1 FROM raw.beneficiary b WHERE b.DESYNPUF_ID = c.DESYNPUF_ID)
  UNION ALL SELECT 'outpatient', COUNT(*) FROM raw.outpatient c
    WHERE NOT EXISTS (SELECT 1 FROM raw.beneficiary b WHERE b.DESYNPUF_ID = c.DESYNPUF_ID)
  UNION ALL SELECT 'carrier', COUNT(*) FROM raw.carrier c
    WHERE NOT EXISTS (SELECT 1 FROM raw.beneficiary b WHERE b.DESYNPUF_ID = c.DESYNPUF_ID)
  UNION ALL SELECT 'pde', COUNT(*) FROM raw.pde c
    WHERE NOT EXISTS (SELECT 1 FROM raw.beneficiary b WHERE b.DESYNPUF_ID = c.DESYNPUF_ID)
"))

# 5. Duplicate claim IDs within a table (look at these before deciding how to treat them)
print(dbGetQuery(con, "
  SELECT 'inpatient' AS tbl, COUNT(*) - COUNT(DISTINCT CLM_ID) AS dup_rows FROM raw.inpatient
  UNION ALL SELECT 'outpatient', COUNT(*) - COUNT(DISTINCT CLM_ID) FROM raw.outpatient
  UNION ALL SELECT 'carrier',    COUNT(*) - COUNT(DISTINCT CLM_ID) FROM raw.carrier
  UNION ALL SELECT 'pde',        COUNT(*) - COUNT(DISTINCT PDE_ID) FROM raw.pde
"))

dir.create("output", showWarnings = FALSE)
write.csv(counts, file.path("output", "validation_row_counts.csv"), row.names = FALSE)

dbDisconnect(con, shutdown = TRUE)
