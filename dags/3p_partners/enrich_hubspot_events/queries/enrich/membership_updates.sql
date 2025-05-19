WITH status_changes AS (
  SELECT
    ch.id_company,
    ch.sale_lead_status,
    ch.ts_updated,
    LAG(ch.sale_lead_status) OVER (PARTITION BY ch.id_company ORDER BY ch.ts_updated) AS prev_status,
    LAG(ch.ts_updated) OVER (PARTITION BY ch.id_company ORDER BY ch.ts_updated) AS prev_ts_updated
  FROM
    datalake_hubspot.company_history AS ch
  WHERE
    ch.sale_lead_status IS NOT NULL
),
status_cochorts AS (
  SELECT
    cc.id_company,
    cc.sale_lead_status,
    cc.ts_updated AS ts_start,
    LEAD(cc.ts_updated) OVER (PARTITION BY cc.id_company ORDER BY cc.ts_updated ASC) AS ts_end
  FROM
    status_changes AS cc
  WHERE
    cc.sale_lead_status != prev_status
    OR cc.prev_status IS NULL
)
SELECT
  CONCAT(ch.id_company, DATE_FORMAT(ch.ts_start, 'yyyyMMddHHmmss')) AS id_membership_update,
  ch.id_company AS id_hubspot,
  ch.sale_lead_status AS hubspot_status,
  ch.ts_end IS NULL AS is_current_cohort,
  ch.ts_start,
  ch.ts_end
FROM
  status_cochorts AS ch