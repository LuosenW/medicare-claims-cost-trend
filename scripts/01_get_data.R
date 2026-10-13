# 01_get_data.R
# Downloads CMS DE-SynPUF Sample 2 (2008 to 2010 synthetic Medicare claims) and unzips it.
# Run from the project root (the folder that holds your .Rproj file).
# Source: https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-claims-synthetic-public-use-files/cms-2008-2010-data-entrepreneurs-synthetic-public-use-file-de-synpuf

options(timeout = 3600)  # carrier and drug files are large; default 60s timeout will fail
# CMS's site refuses some requests that identify as an R script (HTTP 403), so identify as a browser
options(HTTPUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36")

raw_zip <- file.path("data", "raw", "zip")
raw_csv <- file.path("data", "raw", "csv")
dir.create(raw_zip, recursive = TRUE, showWarnings = FALSE)
dir.create(raw_csv, recursive = TRUE, showWarnings = FALSE)

sample <- 2   # Sample 1 is missing its 2010 beneficiary file on the CMS site, so this project uses Sample 2

base_a <- "https://www.cms.gov/research-statistics-data-and-systems/downloadable-public-use-files/synpufs/downloads/"
base_b <- "https://downloads.cms.gov/files/"

# Addresses copied from the CMS DE1.0 Sample 2 download page
files <- list(
  bene_2008  = c(paste0(base_a, "de1_0_2008_beneficiary_summary_file_sample_", sample, ".zip"),
                 paste0(base_b, "DE1_0_2008_Beneficiary_Summary_File_Sample_", sample, ".zip")),
  bene_2009  = c(paste0(base_a, "de1_0_2009_beneficiary_summary_file_sample_", sample, ".zip"),
                 paste0(base_b, "DE1_0_2009_Beneficiary_Summary_File_Sample_", sample, ".zip")),
  bene_2010  = c(paste0(base_a, "de1_0_2010_beneficiary_summary_file_sample_", sample, ".zip"),
                 paste0(base_b, "DE1_0_2010_Beneficiary_Summary_File_Sample_", sample, ".zip")),
  inpatient  = c(paste0(base_a, "de1_0_2008_to_2010_inpatient_claims_sample_", sample, ".zip"),
                 paste0(base_b, "DE1_0_2008_to_2010_Inpatient_Claims_Sample_", sample, ".zip")),
  outpatient = c(paste0(base_a, "de1_0_2008_to_2010_outpatient_claims_sample_", sample, ".zip"),
                 paste0(base_b, "DE1_0_2008_to_2010_Outpatient_Claims_Sample_", sample, ".zip")),
  carrier_a  = paste0(base_b, "DE1_0_2008_to_2010_Carrier_Claims_Sample_", sample, "A.zip"),
  carrier_b  = paste0(base_b, "DE1_0_2008_to_2010_Carrier_Claims_Sample_", sample, "B.zip"),
  pde        = paste0(base_b, "DE1_0_2008_to_2010_Prescription_Drug_Events_Sample_", sample, ".zip")
)

is_good_zip <- function(path) {
  file.exists(path) && file.size(path) > 1000 &&
    !inherits(try(utils::unzip(path, list = TRUE), silent = TRUE), "try-error")
}

download_one <- function(name, urls) {
  dest <- file.path(raw_zip, paste0("s", sample, "_", name, ".zip"))
  if (is_good_zip(dest)) {
    message("Already have ", name, ", skipping")
    return(invisible(dest))
  }
  for (attempt in 1:3) {
    for (u in urls) {
      message("Downloading ", name, " (attempt ", attempt, ") from ", u)
      ok <- try(utils::download.file(u, dest, mode = "wb", quiet = FALSE, method = "libcurl"),
                silent = TRUE)
      if (!inherits(ok, "try-error") && is_good_zip(dest)) return(invisible(dest))
      message("  that address did not work")
    }
    if (attempt < 3) { message("  waiting 20 seconds before trying again"); Sys.sleep(20) }
  }
  stop("Could not download ", name, ". Download it by hand from the CMS Sample 2 page ",
       "and save it as ", dest)
}

for (nm in names(files)) download_one(nm, files[[nm]])

# Unzip everything into data/raw/csv
for (z in list.files(raw_zip, pattern = paste0("^s", sample, "_.*\\.zip$"), full.names = TRUE)) {
  utils::unzip(z, exdir = raw_csv, overwrite = TRUE)
}

# Quick check: you should see 8 CSV files
csvs <- list.files(raw_csv, pattern = "\\.csv$", full.names = TRUE, ignore.case = TRUE)
print(data.frame(file = basename(csvs),
                 size_mb = round(file.size(csvs) / 1024^2, 1)))
if (length(csvs) != 8) warning("Expected 8 CSV files, found ", length(csvs))

# Make sure every CSV is from the chosen sample
wrong <- csvs[!grepl(paste0("Sample_", sample, "[AB]?\\.csv$"), csvs, ignore.case = TRUE)]
if (length(wrong) > 0) warning("These CSVs are not from Sample ", sample, ": ", paste(basename(wrong), collapse = ", "))
