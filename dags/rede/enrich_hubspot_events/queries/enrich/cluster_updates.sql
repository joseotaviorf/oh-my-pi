WITH cluster_changes AS (
  SELECT
    ch.id_company,
    ch.company_cluster,
    ch.ts_updated,
    LAG(ch.company_cluster) OVER (PARTITION BY ch.id_company ORDER BY ch.ts_updated) AS prev_cluster,
    LAG(ch.ts_updated) OVER (PARTITION BY ch.id_company ORDER BY ch.ts_updated) AS prev_ts_updated
  FROM
    datalake_hubspot.company_history AS ch
  WHERE
    ch.company_cluster != 'Sim'
    AND ch.company_cluster IS NOT NULL
),
cluster_cochorts AS (
  SELECT
    cc.id_company,
    cc.company_cluster,
    cc.ts_updated AS ts_start,
    LEAD(cc.ts_updated) OVER (PARTITION BY cc.id_company ORDER BY cc.ts_updated ASC) AS ts_end
  FROM
    cluster_changes AS cc
  WHERE
    cc.company_cluster != prev_cluster 
    OR cc.prev_cluster IS NULL
)
SELECT
  CONCAT(ch.id_company, DATE_FORMAT(ch.ts_start, 'yyyyMMddHHmmss')) AS id_cluster_update,
  ch.id_company AS id_hubspot,
  ch.company_cluster,
  ch.ts_end IS NULL AS is_current_cohort,
  ch.ts_start,
  ch.ts_end
FROM
  cluster_cochorts AS ch