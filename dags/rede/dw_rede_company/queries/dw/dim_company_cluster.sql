WITH cluster_changes AS (
  SELECT
    ch.id_company,
    ch.name AS company_name,
    ch.extracted_3p_tag AS company_extracted_3p_tag,
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
    cc.company_name,
    cc.company_extracted_3p_tag,
    cc.company_cluster,
    cc.ts_updated AS ts_cluster_start,
    LEAD(cc.ts_updated) OVER (PARTITION BY cc.id_company ORDER BY cc.ts_updated ASC) AS ts_cluster_end
  FROM
    cluster_changes AS cc
  WHERE
    cc.company_cluster != prev_cluster 
      OR cc.prev_cluster IS NULL
),
decola_cohorts AS (
  SELECT
    ch.id_company,
    MAX(ch.ts_cluster_end) AS ts_decola_cohort_end
  FROM
    cluster_cochorts AS ch
  WHERE
    ch.ts_cluster_end IS NOT NULL
      AND (
        ch.company_cluster LIKE 'Decola%' 
        OR ch.company_cluster LIKE 'Comunidade%'
      )
  GROUP BY
    1
)
SELECT
  MD5(ch.id_company || COALESCE(ch.company_cluster, CAST(FALSE AS STRING)) || ch.ts_cluster_start) AS sk_company_cluster,
  ch.id_company AS sk_company_hubspot,
  ch.company_name,
  ch.company_extracted_3p_tag,
  ch.company_cluster,
  ch.company_cluster LIKE 'Decola%' OR ch.company_cluster LIKE 'Comunidade%' AS is_decola_community,
  ch.company_cluster LIKE 'Decola%' OR ch.company_cluster LIKE 'Comunidade%' AND ch.ts_cluster_end IS NULL AS is_decola_current_cohort,
  dc.id_company IS NOT NULL AND ch.ts_cluster_start >= dc.ts_decola_cohort_end AS is_ex_decola,
  CAST(DATEADD(DAY, 1, DATE_TRUNC('WEEK', ch.ts_cluster_start)) AS DATE) AS dt_week_cluster_start,
  CAST(DATEADD(DAY, 1, DATE_TRUNC('WEEK', ch.ts_cluster_end)) AS DATE) AS dt_week_cluster_end,
  ch.ts_cluster_start,
  ch.ts_cluster_end
FROM
  cluster_cochorts AS ch
LEFT JOIN
  decola_cohorts AS dc
    ON ch.id_company = dc.id_company