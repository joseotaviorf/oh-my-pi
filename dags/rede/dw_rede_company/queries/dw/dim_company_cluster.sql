WITH cluster_changes AS (
  SELECT
    ch.id_company,
    ch.name AS company_name,
    ch.company_cluster,
    ch.ts_updated,
    LAG(ch.company_cluster) OVER (PARTITION BY ch.id_company ORDER BY ch.ts_updated) AS prev_cluster,
    LAG(ch.ts_updated) OVER (PARTITION BY ch.id_company ORDER BY ch.ts_updated) AS prev_ts_updated
  FROM
    datalake_hubspot.company_history AS ch
  WHERE 
    ch.company_cluster != 'Sim' 
    AND ch.company_cluster IS NOT NULL
)

SELECT
  MD5(CONCAT(cc.id_company, cc.company_cluster, cc.ts_updated)) AS sk_company_cluster,
  cc.id_company AS sk_company_hubspot,
  cc.company_name,
  cc.company_cluster,
  cc.company_cluster LIKE 'Decola%' AS is_decola_community,
  cc.company_cluster LIKE 'Decola%' AND LEAD(cc.ts_updated) OVER (PARTITION BY cc.id_company ORDER BY cc.ts_updated ASC) IS NULL AS is_decola_current_cohort,
  cc.ts_updated AS ts_cluster_start,
  LEAD(cc.ts_updated) OVER (PARTITION BY cc.id_company ORDER BY cc.ts_updated ASC) AS ts_cluster_end
FROM
  cluster_changes AS cc
WHERE
  cc.company_cluster != prev_cluster 
  OR cc.prev_cluster IS NULL