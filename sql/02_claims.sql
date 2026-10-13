-- 02_claims.sql
-- One unified claims table, one row per claim (per drug event for pharmacy), with:
--   service_category : Inpatient, Outpatient, Professional, Pharmacy
--   paid             : what Medicare (or the Part D plan) paid
--   member_cost      : deductible + coinsurance the member owed
--   allowed          : paid + member_cost + other primary payer
--   units            : the utilization count used for "per 1,000"
--                      (admissions, visits, service lines, scripts)
--   days             : inpatient days (inpatient only)

-- Inpatient: some claims are split into segments (same CLM_ID on more than one row),
-- so roll them up to one row per claim.
CREATE OR REPLACE TABLE clean.claims_ip AS
SELECT
  DESYNPUF_ID                                                     AS member_id,
  CLM_ID                                                          AS claim_id,
  MIN(TRY_STRPTIME(CLM_FROM_DT, '%Y%m%d'))::DATE                  AS service_dt,
  SUM(COALESCE(TRY_CAST(CLM_PMT_AMT AS DOUBLE), 0))               AS paid,
  SUM(COALESCE(TRY_CAST(NCH_BENE_IP_DDCTBL_AMT AS DOUBLE), 0)
    + COALESCE(TRY_CAST(NCH_BENE_PTA_COINSRNC_LBLTY_AM AS DOUBLE), 0)
    + COALESCE(TRY_CAST(NCH_BENE_BLOOD_DDCTBL_LBLTY_AM AS DOUBLE), 0)) AS member_cost,
  SUM(COALESCE(TRY_CAST(NCH_PRMRY_PYR_CLM_PD_AMT AS DOUBLE), 0))  AS other_payer,
  SUM(COALESCE(TRY_CAST(CLM_UTLZTN_DAY_CNT AS DOUBLE), 0))        AS days,
  COUNT(*)                                                        AS n_segments
FROM raw.inpatient
GROUP BY DESYNPUF_ID, CLM_ID;

CREATE OR REPLACE TABLE clean.claims_op AS
SELECT
  DESYNPUF_ID                                                     AS member_id,
  CLM_ID                                                          AS claim_id,
  MIN(TRY_STRPTIME(CLM_FROM_DT, '%Y%m%d'))::DATE                  AS service_dt,
  SUM(COALESCE(TRY_CAST(CLM_PMT_AMT AS DOUBLE), 0))               AS paid,
  SUM(COALESCE(TRY_CAST(NCH_BENE_PTB_DDCTBL_AMT AS DOUBLE), 0)
    + COALESCE(TRY_CAST(NCH_BENE_PTB_COINSRNC_AMT AS DOUBLE), 0)
    + COALESCE(TRY_CAST(NCH_BENE_BLOOD_DDCTBL_LBLTY_AM AS DOUBLE), 0)) AS member_cost,
  SUM(COALESCE(TRY_CAST(NCH_PRMRY_PYR_CLM_PD_AMT AS DOUBLE), 0))  AS other_payer
FROM raw.outpatient
GROUP BY DESYNPUF_ID, CLM_ID;

-- Carrier (professional) claims store up to 13 service lines side by side.
-- UNNEST turns the 13 columns into 13 rows per claim (lists unnest in parallel),
-- then lines with an allowed amount are rolled back up to one row per claim.
CREATE OR REPLACE TABLE clean.claims_prof AS
WITH lines AS (
  SELECT
    DESYNPUF_ID, CLM_ID, CLM_FROM_DT,
    UNNEST([LINE_NCH_PMT_AMT_1, LINE_NCH_PMT_AMT_2, LINE_NCH_PMT_AMT_3, LINE_NCH_PMT_AMT_4, LINE_NCH_PMT_AMT_5, LINE_NCH_PMT_AMT_6, LINE_NCH_PMT_AMT_7, LINE_NCH_PMT_AMT_8, LINE_NCH_PMT_AMT_9, LINE_NCH_PMT_AMT_10, LINE_NCH_PMT_AMT_11, LINE_NCH_PMT_AMT_12, LINE_NCH_PMT_AMT_13]) AS pmt,
    UNNEST([LINE_ALOWD_CHRG_AMT_1, LINE_ALOWD_CHRG_AMT_2, LINE_ALOWD_CHRG_AMT_3, LINE_ALOWD_CHRG_AMT_4, LINE_ALOWD_CHRG_AMT_5, LINE_ALOWD_CHRG_AMT_6, LINE_ALOWD_CHRG_AMT_7, LINE_ALOWD_CHRG_AMT_8, LINE_ALOWD_CHRG_AMT_9, LINE_ALOWD_CHRG_AMT_10, LINE_ALOWD_CHRG_AMT_11, LINE_ALOWD_CHRG_AMT_12, LINE_ALOWD_CHRG_AMT_13]) AS alowd,
    UNNEST([LINE_BENE_PTB_DDCTBL_AMT_1, LINE_BENE_PTB_DDCTBL_AMT_2, LINE_BENE_PTB_DDCTBL_AMT_3, LINE_BENE_PTB_DDCTBL_AMT_4, LINE_BENE_PTB_DDCTBL_AMT_5, LINE_BENE_PTB_DDCTBL_AMT_6, LINE_BENE_PTB_DDCTBL_AMT_7, LINE_BENE_PTB_DDCTBL_AMT_8, LINE_BENE_PTB_DDCTBL_AMT_9, LINE_BENE_PTB_DDCTBL_AMT_10, LINE_BENE_PTB_DDCTBL_AMT_11, LINE_BENE_PTB_DDCTBL_AMT_12, LINE_BENE_PTB_DDCTBL_AMT_13]) AS ded,
    UNNEST([LINE_COINSRNC_AMT_1, LINE_COINSRNC_AMT_2, LINE_COINSRNC_AMT_3, LINE_COINSRNC_AMT_4, LINE_COINSRNC_AMT_5, LINE_COINSRNC_AMT_6, LINE_COINSRNC_AMT_7, LINE_COINSRNC_AMT_8, LINE_COINSRNC_AMT_9, LINE_COINSRNC_AMT_10, LINE_COINSRNC_AMT_11, LINE_COINSRNC_AMT_12, LINE_COINSRNC_AMT_13]) AS coins,
    UNNEST([LINE_BENE_PRMRY_PYR_PD_AMT_1, LINE_BENE_PRMRY_PYR_PD_AMT_2, LINE_BENE_PRMRY_PYR_PD_AMT_3, LINE_BENE_PRMRY_PYR_PD_AMT_4, LINE_BENE_PRMRY_PYR_PD_AMT_5, LINE_BENE_PRMRY_PYR_PD_AMT_6, LINE_BENE_PRMRY_PYR_PD_AMT_7, LINE_BENE_PRMRY_PYR_PD_AMT_8, LINE_BENE_PRMRY_PYR_PD_AMT_9, LINE_BENE_PRMRY_PYR_PD_AMT_10, LINE_BENE_PRMRY_PYR_PD_AMT_11, LINE_BENE_PRMRY_PYR_PD_AMT_12, LINE_BENE_PRMRY_PYR_PD_AMT_13]) AS prim
  FROM raw.carrier
)
SELECT
  DESYNPUF_ID                                                     AS member_id,
  CLM_ID                                                          AS claim_id,
  MIN(TRY_STRPTIME(CLM_FROM_DT, '%Y%m%d'))::DATE                  AS service_dt,
  SUM(COALESCE(TRY_CAST(pmt AS DOUBLE), 0))                       AS paid,
  SUM(COALESCE(TRY_CAST(ded AS DOUBLE), 0) + COALESCE(TRY_CAST(coins AS DOUBLE), 0)) AS member_cost,
  SUM(COALESCE(TRY_CAST(prim AS DOUBLE), 0))                      AS other_payer,
  SUM(COALESCE(TRY_CAST(alowd AS DOUBLE), 0))                     AS allowed_reported,
  COUNT(*) FILTER (WHERE TRY_CAST(alowd AS DOUBLE) > 0)           AS service_lines
FROM lines
GROUP BY DESYNPUF_ID, CLM_ID;

-- Pharmacy. In about 5% of synthetic drug events the patient pay is larger than the total drug cost,
-- which cannot happen in real claims (the synthetic process generated the two fields almost independently).
-- Decision: cap patient pay at total cost, so plan paid = total cost - capped patient pay, never below 0.
-- This keeps pharmacy on the same plan paid basis as the other categories. See notes/decisions.md.
CREATE OR REPLACE TABLE clean.claims_rx AS
WITH typed AS (
  SELECT
    DESYNPUF_ID                                                   AS member_id,
    PDE_ID                                                        AS claim_id,
    TRY_STRPTIME(SRVC_DT, '%Y%m%d')::DATE                         AS service_dt,
    COALESCE(TRY_CAST(TOT_RX_CST_AMT AS DOUBLE), 0)               AS total_cost,
    COALESCE(TRY_CAST(PTNT_PAY_AMT AS DOUBLE), 0)                 AS patient_pay_reported,
    COALESCE(TRY_CAST(DAYS_SUPLY_NUM AS DOUBLE), 0)               AS days_supply
  FROM raw.pde
)
SELECT
  member_id, claim_id, service_dt,
  total_cost - LEAST(patient_pay_reported, total_cost)            AS paid,
  LEAST(patient_pay_reported, total_cost)                         AS member_cost,
  total_cost                                                      AS allowed,
  patient_pay_reported,
  patient_pay_reported > total_cost                               AS patient_pay_capped,
  days_supply
FROM typed;

-- Stack the four sources into one table
CREATE OR REPLACE TABLE clean.claims AS
SELECT member_id, claim_id, 'Inpatient' AS service_category, service_dt, YEAR(service_dt) AS year,
       paid, member_cost, paid + member_cost + other_payer AS allowed,
       1.0 AS units, days
FROM clean.claims_ip
UNION ALL
SELECT member_id, claim_id, 'Outpatient', service_dt, YEAR(service_dt),
       paid, member_cost, paid + member_cost + other_payer,
       1.0, 0
FROM clean.claims_op
UNION ALL
SELECT member_id, claim_id, 'Professional', service_dt, YEAR(service_dt),
       paid, member_cost, allowed_reported,
       service_lines, 0
FROM clean.claims_prof
UNION ALL
SELECT member_id, claim_id, 'Pharmacy', service_dt, YEAR(service_dt),
       paid, member_cost, allowed,
       1.0, 0
FROM clean.claims_rx;

-- Claims outside 2008 to 2010 or with no usable date are kept out of the analysis table
-- (counted in the reconciliation step so nothing disappears silently).
CREATE OR REPLACE VIEW clean.claims_in_scope AS
SELECT * FROM clean.claims WHERE year BETWEEN 2008 AND 2010;
