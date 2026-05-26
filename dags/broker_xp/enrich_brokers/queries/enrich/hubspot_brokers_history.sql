WITH brokers_members_ranked AS (
  SELECT
    c.id_company,
    c.cnpj,
    ROW_NUMBER() OVER(PARTITION BY c.cnpj ORDER BY c.ts_updated DESC) AS rn
  FROM
    datalake_hubspot.company AS c
  WHERE
    c.has_been_sale_member
      AND NOT(c.is_archived)
      AND NOT(c.is_merged_into_other_company)
),
brokers_members AS (
  SELECT
    bmr.id_company,
    bmr.cnpj
  FROM
    brokers_members_ranked AS bmr
  WHERE
    bmr.rn = 1
),
broker_history AS (
  SELECT
    cb.sk_broker,
    ch.id_company AS id_hubspot_company,
    ch.id_hubspot_owner,
    ch.cnpj,
    CASE
      WHEN ch.sale_lead_status = 'Membro' THEN 'ACTIVE'
      ELSE 'INACTIVE'
    END AS broker_status,
    ch.company_cluster,
    ch.cluster_performance,
    ch.ts_updated,
    TRUE AS has_3p_access_control,
    LAG(
      CASE
        WHEN ch.sale_lead_status = 'Membro' THEN 'ACTIVE'
        ELSE 'INACTIVE'
      END
    ) OVER (PARTITION BY cb.sk_broker ORDER BY ch.ts_updated) AS prev_broker_status,
    LAG(ch.company_cluster) OVER (PARTITION BY cb.sk_broker ORDER BY ch.ts_updated) AS prev_company_cluster,
    LAG(ch.cluster_performance) OVER (PARTITION BY cb.sk_broker ORDER BY ch.ts_updated) AS prev_cluster_performance,
    LAG(ch.id_hubspot_owner) OVER (PARTITION BY cb.sk_broker ORDER BY ch.ts_updated) AS prev_id_hubspot_owner
  FROM
    datalake_hubspot.company_history AS ch
  INNER JOIN
    brokers_members AS bm
      ON ch.id_company = bm.id_company
  INNER JOIN
    core_brokers.brokers AS cb
      ON bm.cnpj = cb.cnpj
)
SELECT
  bh.sk_broker,
  bh.id_hubspot_company,
  bh.id_hubspot_owner,
  bh.cnpj,
  bh.broker_status,
  bh.company_cluster,
  bh.cluster_performance,
  ROW_NUMBER() OVER(PARTITION BY bh.id_hubspot_company ORDER BY bh.ts_updated DESC) AS broker_version,
  ROW_NUMBER() OVER(PARTITION BY bh.id_hubspot_company ORDER BY bh.ts_updated DESC) = 1 AS is_current,
  bh.has_3p_access_control,
  bh.ts_updated,
  CURRENT_TIMESTAMP() AS ts_load
FROM
  broker_history AS bh
WHERE
  bh.broker_status != bh.prev_broker_status
  OR bh.company_cluster != bh.prev_company_cluster
  OR bh.cluster_performance != bh.prev_cluster_performance
  OR bh.id_hubspot_owner IS DISTINCT FROM bh.prev_id_hubspot_owner
  OR bh.prev_broker_status IS NULL