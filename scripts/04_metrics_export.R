# 04_metrics_export.R
# Builds the metrics tables in DuckDB and exports each one to output/tables as CSV
# (these CSVs feed the charts, the Power BI dashboard and the README).

library(DBI)
library(duckdb)

con <- dbConnect(duckdb(), dbdir = file.path("db", "synpuf.duckdb"))

run_sql_file <- function(con, path) {
  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
  stmts <- strsplit(txt, ";[ \t]*(\n|$)")[[1]]
  for (s in stmts) {
    if (nchar(trimws(gsub("--[^\n]*", "", s))) == 0) next
    dbExecute(con, s)
  }
  message("Ran ", path)
}

run_sql_file(con, file.path("sql", "03_metrics.sql"))

out_dir <- file.path("output", "tables")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Small summary tables only; member_cost is member level, so it is exported in a de-identified,
# banded form below instead of row by row.
tables <- c("category_year", "total_year", "trend", "hcc_summary",
            "hcc_profile", "cost_concentration", "chronic")

for (t in tables) {
  df <- dbGetQuery(con, paste0("SELECT * FROM metrics.", t, " ORDER BY ALL"))
  write.csv(df, file.path(out_dir, paste0(t, ".csv")), row.names = FALSE, na = "")
  message("Exported ", t, " (", nrow(df), " rows)")
}

# Cost bands for the dashboard (how many members fall in each annual cost range)
bands <- dbGetQuery(con, "
  SELECT year,
         CASE
           WHEN total_paid = 0        THEN '1. $0'
           WHEN total_paid < 1000     THEN '2. Under $1K'
           WHEN total_paid < 10000    THEN '3. $1K to $10K'
           WHEN total_paid < 50000    THEN '4. $10K to $50K'
           WHEN total_paid < 100000   THEN '5. $50K to $100K'
           ELSE                            '6. $100K and over'
         END AS cost_band,
         COUNT(*)        AS members,
         SUM(total_paid) AS paid
  FROM metrics.member_cost
  GROUP BY ALL
  ORDER BY ALL
")
write.csv(bands, file.path(out_dir, "cost_bands.csv"), row.names = FALSE, na = "")

# Print the headline numbers you will quote in the README and resume
print(dbGetQuery(con, "SELECT * FROM metrics.total_year ORDER BY year"))
print(dbGetQuery(con, "SELECT year, service_category, paid_pmpm, util_per_1000, unit_cost FROM metrics.category_year ORDER BY year, service_category"))
print(dbGetQuery(con, "SELECT * FROM metrics.trend WHERE year = 2009 ORDER BY service_category"))
print(dbGetQuery(con, "SELECT * FROM metrics.hcc_summary ORDER BY year"))

dbDisconnect(con, shutdown = TRUE)
