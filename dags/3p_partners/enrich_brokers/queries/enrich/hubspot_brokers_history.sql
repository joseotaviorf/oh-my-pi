WITH brokers_members AS (
  SELECT
    c.id_company,
    c.cnpj
  FROM
    datalake_hubspot.company AS c
  WHERE
    c.has_been_sale_member
      AND NOT(c.is_archived)
      AND NOT(c.is_merged_into_other_company)
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY c.cnpj ORDER BY c.ts_updated DESC) = 1
)
SELECT
  cb.sk_broker,
  ch.id_company,
  ch.id_hubspot_owner,
  CASE
    WHEN ch.sale_lead_status = 'Membro' THEN 'ACTIVE'
    ELSE 'INACTIVE'
  END AS broker_status,
  ch.company_cluster,
  ch.cluster_performance,
  ROW_NUMBER() OVER(PARTITION BY cb.sk_broker ORDER BY ch.ts_updated DESC) = 1 AS is_current,
  TRUE AS has_3p_access_control,
  ch.ts_updated,
  CURRENT_TIMESTAMP() AS ts_load
FROM
  datalake_hubspot.company_history AS ch
INNER JOIN
  brokers_members AS bm
    ON ch.id_company = bm.id_company
INNER JOIN
  core_brokers.brokers AS cb
    ON bm.cnpj = cb.cnpj
WHERE
  ch.ts_updated >= '{load_start_date}'