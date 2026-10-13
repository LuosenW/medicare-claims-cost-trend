-- 01_clean_members.sql
-- One row per member per year with demographics, chronic condition flags and member months (exposure).
-- Exposure is split by Medicare part because each part pays for different services:
--   Part A months -> inpatient, Part B months -> outpatient and professional, Part D months -> pharmacy.
-- Months spent in a Medicare Advantage (HMO) plan are removed from A and B exposure,
-- because fee for service claims do not exist for those months.

CREATE SCHEMA IF NOT EXISTS clean;

CREATE OR REPLACE TABLE clean.member_year AS
WITH typed AS (
  SELECT
    DESYNPUF_ID                                        AS member_id,
    file_year                                          AS year,
    TRY_STRPTIME(BENE_BIRTH_DT, '%Y%m%d')::DATE        AS birth_dt,
    TRY_STRPTIME(BENE_DEATH_DT, '%Y%m%d')::DATE        AS death_dt,
    CASE BENE_SEX_IDENT_CD WHEN '1' THEN 'Male' WHEN '2' THEN 'Female' END AS sex,
    BENE_ESRD_IND = 'Y'                                AS esrd,
    SP_STATE_CODE                                      AS state_code,
    COALESCE(TRY_CAST(BENE_HI_CVRAGE_TOT_MONS  AS INTEGER), 0) AS months_a,
    COALESCE(TRY_CAST(BENE_SMI_CVRAGE_TOT_MONS AS INTEGER), 0) AS months_b,
    COALESCE(TRY_CAST(BENE_HMO_CVRAGE_TOT_MONS AS INTEGER), 0) AS months_hmo,
    COALESCE(TRY_CAST(PLAN_CVRG_MOS_NUM        AS INTEGER), 0) AS months_d,
    -- chronic condition flags: 1 = yes, 2 = no
    (SP_ALZHDMTA = '1')::INTEGER AS cc_alzheimers,
    (SP_CHF      = '1')::INTEGER AS cc_heart_failure,
    (SP_CHRNKIDN = '1')::INTEGER AS cc_kidney,
    (SP_CNCR     = '1')::INTEGER AS cc_cancer,
    (SP_COPD     = '1')::INTEGER AS cc_copd,
    (SP_DEPRESSN = '1')::INTEGER AS cc_depression,
    (SP_DIABETES = '1')::INTEGER AS cc_diabetes,
    (SP_ISCHMCHT = '1')::INTEGER AS cc_ischemic_heart,
    (SP_OSTEOPRS = '1')::INTEGER AS cc_osteoporosis,
    (SP_RA_OA    = '1')::INTEGER AS cc_arthritis,
    (SP_STRKETIA = '1')::INTEGER AS cc_stroke,
    -- annual payment totals CMS put on the beneficiary file (used only to reconcile against claims)
    COALESCE(TRY_CAST(MEDREIMB_IP  AS DOUBLE), 0) AS bene_file_paid_ip,
    COALESCE(TRY_CAST(MEDREIMB_OP  AS DOUBLE), 0) AS bene_file_paid_op,
    COALESCE(TRY_CAST(MEDREIMB_CAR AS DOUBLE), 0) AS bene_file_paid_car
  FROM raw.beneficiary
)
SELECT
  *,
  year - YEAR(birth_dt)                                 AS age,
  CASE
    WHEN year - YEAR(birth_dt) < 65 THEN 'Under 65'
    WHEN year - YEAR(birth_dt) < 75 THEN '65 to 74'
    WHEN year - YEAR(birth_dt) < 85 THEN '75 to 84'
    ELSE '85 and over'
  END                                                   AS age_band,
  GREATEST(months_a - months_hmo, 0)                    AS mm_a,
  GREATEST(months_b - months_hmo, 0)                    AS mm_b,
  months_d                                              AS mm_d,
  cc_alzheimers + cc_heart_failure + cc_kidney + cc_cancer + cc_copd + cc_depression
    + cc_diabetes + cc_ischemic_heart + cc_osteoporosis + cc_arthritis + cc_stroke AS n_chronic
FROM typed;

-- Exposure summary by year
CREATE OR REPLACE VIEW clean.exposure AS
SELECT
  year,
  COUNT(*)            AS members,
  SUM(mm_a)           AS mm_a,
  SUM(mm_b)           AS mm_b,
  SUM(mm_d)           AS mm_d
FROM clean.member_year
GROUP BY year;
