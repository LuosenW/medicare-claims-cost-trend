-- 03_metrics.sql
-- Core health plan metrics. Every table here is exported to output/tables for the dashboard.
--
-- Definitions (put these in the README):
--   PMPM            = paid / member months
--   Util per 1,000  = units / member months * 12,000   (annualized, per 1,000 members)
--   Unit cost       = paid / units
--   So PMPM = (Util per 1,000 / 12,000) * Unit cost, which lets PMPM trend split exactly into
--   a utilization piece and a unit cost piece: (1 + PMPM trend) = (1 + util trend) * (1 + unit cost trend).
--   Exposure: Inpatient uses Part A months, Outpatient and Professional use Part B months,
--   Pharmacy uses Part D months (fee for service months only for A and B).

CREATE SCHEMA IF NOT EXISTS metrics;

-- 1. PMPM, utilization and unit cost by year and service category
CREATE OR REPLACE TABLE metrics.category_year AS
WITH cost AS (
  SELECT year, service_category,
         COUNT(*)          AS claims,
         SUM(paid)         AS paid,
         SUM(allowed)      AS allowed,
         SUM(member_cost)  AS member_cost,
         SUM(units)        AS units,
         SUM(days)         AS ip_days
  FROM clean.claims_in_scope
  GROUP BY year, service_category
),
joined AS (
  SELECT c.*,
         CASE c.service_category
           WHEN 'Inpatient' THEN e.mm_a
           WHEN 'Pharmacy'  THEN e.mm_d
           ELSE e.mm_b
         END AS member_months,
         CASE c.service_category
           WHEN 'Inpatient'    THEN 'Admissions'
           WHEN 'Outpatient'   THEN 'Visits'
           WHEN 'Professional' THEN 'Services'
           WHEN 'Pharmacy'     THEN 'Scripts'
         END AS unit_label
  FROM cost c
  JOIN clean.exposure e USING (year)
)
SELECT *,
       paid / member_months                     AS paid_pmpm,
       allowed / member_months                  AS allowed_pmpm,
       units / member_months * 12000            AS util_per_1000,
       paid / NULLIF(units, 0)                  AS unit_cost,
       CASE WHEN service_category = 'Inpatient'
            THEN ip_days / member_months * 12000 END AS ip_days_per_1000,
       CASE WHEN service_category = 'Inpatient'
            THEN ip_days / NULLIF(units, 0) END       AS avg_length_of_stay
FROM joined;

-- 2. Total PMPM by year (sum of the category PMPMs, each on its own exposure)
CREATE OR REPLACE TABLE metrics.total_year AS
SELECT year,
       SUM(paid_pmpm)     AS paid_pmpm,
       SUM(allowed_pmpm)  AS allowed_pmpm,
       SUM(paid)          AS paid
FROM metrics.category_year
GROUP BY year;

-- 3. Year over year trend split into utilization and unit cost.
--    The dollar split uses logs so the two pieces add up exactly to the PMPM change.
CREATE OR REPLACE TABLE metrics.trend AS
SELECT
  cur.year,
  cur.service_category,
  prev.paid_pmpm                                             AS prior_pmpm,
  cur.paid_pmpm                                              AS current_pmpm,
  cur.paid_pmpm - prev.paid_pmpm                             AS pmpm_change,
  cur.paid_pmpm / prev.paid_pmpm - 1                         AS pmpm_trend,
  cur.util_per_1000 / prev.util_per_1000 - 1                 AS util_trend,
  cur.unit_cost / prev.unit_cost - 1                         AS unit_cost_trend,
  (cur.paid_pmpm - prev.paid_pmpm)
    * LN(cur.util_per_1000 / prev.util_per_1000)
    / NULLIF(LN(cur.paid_pmpm / prev.paid_pmpm), 0)          AS util_effect_pmpm,
  (cur.paid_pmpm - prev.paid_pmpm)
    * LN(cur.unit_cost / prev.unit_cost)
    / NULLIF(LN(cur.paid_pmpm / prev.paid_pmpm), 0)          AS unit_cost_effect_pmpm
FROM metrics.category_year cur
JOIN metrics.category_year prev
  ON prev.service_category = cur.service_category
 AND prev.year = cur.year - 1;

-- 4. Member level annual cost (base for high cost claimant and chronic condition views)
CREATE OR REPLACE TABLE metrics.member_cost AS
SELECT
  m.member_id, m.year, m.sex, m.age_band, m.n_chronic, m.mm_a, m.mm_b, m.mm_d,
  COALESCE(SUM(c.paid), 0)                                                  AS total_paid,
  COALESCE(SUM(c.paid) FILTER (WHERE c.service_category = 'Inpatient'), 0)    AS paid_ip,
  COALESCE(SUM(c.paid) FILTER (WHERE c.service_category = 'Outpatient'), 0)   AS paid_op,
  COALESCE(SUM(c.paid) FILTER (WHERE c.service_category = 'Professional'), 0) AS paid_prof,
  COALESCE(SUM(c.paid) FILTER (WHERE c.service_category = 'Pharmacy'), 0)     AS paid_rx
FROM clean.member_year m
LEFT JOIN clean.claims_in_scope c
  ON c.member_id = m.member_id AND c.year = m.year
GROUP BY m.member_id, m.year, m.sex, m.age_band, m.n_chronic, m.mm_a, m.mm_b, m.mm_d;

-- 5. High cost claimants: how much of total cost sits with the top 1%, 5%, 10% of members
CREATE OR REPLACE TABLE metrics.hcc_summary AS
WITH ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY year ORDER BY total_paid DESC) AS rn,
         COUNT(*)     OVER (PARTITION BY year)                          AS n
  FROM metrics.member_cost
)
SELECT
  year,
  MAX(n)                                                                AS members,
  SUM(total_paid)                                                       AS total_paid,
  MIN(total_paid) FILTER (WHERE rn <= n * 0.01)                         AS top_1pct_threshold,
  SUM(total_paid) FILTER (WHERE rn <= n * 0.01) / SUM(total_paid)       AS share_top_1pct,
  SUM(total_paid) FILTER (WHERE rn <= n * 0.05) / SUM(total_paid)       AS share_top_5pct,
  SUM(total_paid) FILTER (WHERE rn <= n * 0.10) / SUM(total_paid)       AS share_top_10pct,
  COUNT(*) FILTER (WHERE total_paid >= 50000)                           AS members_over_50k,
  SUM(total_paid) FILTER (WHERE total_paid >= 50000) / SUM(total_paid)  AS share_over_50k,
  COUNT(*) FILTER (WHERE total_paid = 0) * 1.0 / MAX(n)                 AS pct_members_no_claims
FROM ranked
GROUP BY year;

-- 6. Profile of the top 1% versus everyone else
CREATE OR REPLACE TABLE metrics.hcc_profile AS
WITH ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY year ORDER BY total_paid DESC) AS rn,
         COUNT(*)     OVER (PARTITION BY year)                          AS n
  FROM metrics.member_cost
)
SELECT
  year,
  CASE WHEN rn <= n * 0.01 THEN 'Top 1%' ELSE 'Other 99%' END   AS member_group,
  COUNT(*)                                                      AS members,
  AVG(total_paid)                                               AS avg_annual_paid,
  AVG(n_chronic)                                                AS avg_chronic_conditions,
  SUM(paid_ip)   / NULLIF(SUM(total_paid), 0)                   AS share_inpatient,
  SUM(paid_op)   / NULLIF(SUM(total_paid), 0)                   AS share_outpatient,
  SUM(paid_prof) / NULLIF(SUM(total_paid), 0)                   AS share_professional,
  SUM(paid_rx)   / NULLIF(SUM(total_paid), 0)                   AS share_pharmacy
FROM ranked
GROUP BY ALL;

-- 7. Cost concentration curve, one point per percentile of members (for a chart)
CREATE OR REPLACE TABLE metrics.cost_concentration AS
WITH ranked AS (
  SELECT year, total_paid,
         ROW_NUMBER() OVER (PARTITION BY year ORDER BY total_paid DESC) AS rn,
         COUNT(*)     OVER (PARTITION BY year)                          AS n,
         SUM(total_paid) OVER (PARTITION BY year ORDER BY total_paid DESC
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_paid,
         SUM(total_paid) OVER (PARTITION BY year)                       AS year_paid
  FROM metrics.member_cost
)
SELECT year,
       CEIL(rn * 100.0 / n)            AS top_pct_of_members,
       MAX(cum_paid / year_paid)       AS cum_share_of_cost
FROM ranked
GROUP BY year, CEIL(rn * 100.0 / n);

-- 8. Cost by number of chronic conditions.
--    Medical (inpatient + outpatient + professional) is put on Part B months as a simplification;
--    note this in the README.
CREATE OR REPLACE TABLE metrics.chronic AS
SELECT
  year,
  CASE WHEN n_chronic >= 6 THEN '6+' ELSE CAST(n_chronic AS VARCHAR) END AS chronic_conditions,
  COUNT(*)                                                       AS members,
  SUM(paid_ip + paid_op + paid_prof) / NULLIF(SUM(mm_b), 0)      AS medical_pmpm,
  SUM(paid_rx) / NULLIF(SUM(mm_d), 0)                            AS pharmacy_pmpm
FROM metrics.member_cost
GROUP BY ALL;
