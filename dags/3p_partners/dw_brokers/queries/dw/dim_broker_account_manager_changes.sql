WITH owner_changes AS (
  SELECT
    hbh.sk_broker,
    hbh.id_hubspot_owner,
    hbh.ts_updated,
    LAG(hbh.id_hubspot_owner) OVER (PARTITION BY hbh.sk_broker ORDER BY hbh.ts_updated) AS prev_id_hubspot_owner
  FROM
    datalake_brokers.hubspot_brokers_history AS hbh
),
filtered_changes AS (
  SELECT
    oc.sk_broker,
    oc.id_hubspot_owner,
    ROW_NUMBER() OVER (PARTITION BY oc.sk_broker ORDER BY oc.ts_updated) AS version,
    oc.ts_updated
  FROM
    owner_changes AS oc
  WHERE
    oc.id_hubspot_owner IS NOT NULL
    AND (oc.id_hubspot_owner != oc.prev_id_hubspot_owner OR oc.prev_id_hubspot_owner IS NULL)
)
SELECT
  CONCAT(
    CAST(fc.sk_broker AS STRING),
    CAST(COALESCE(ps.id_person, -1) AS STRING),
    CAST(fc.version AS STRING)
  ) AS sk_account_manager_change,
  fc.sk_broker AS sk_broker,
  COALESCE(ps.sk_person, -1) AS sk_person_account_manager,
  fc.version,
  LEAD(fc.ts_updated) OVER (PARTITION BY fc.sk_broker ORDER BY fc.ts_updated) IS NULL AS is_current,
  TRUE AS has_3p_access_control,
  fc.ts_updated AS ts_start,
  LEAD(fc.ts_updated) OVER (PARTITION BY fc.sk_broker ORDER BY fc.ts_updated) AS ts_end,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(fc.ts_updated) AS year,
  MONTH(fc.ts_updated) AS month,
  DAY(fc.ts_updated) AS day
FROM
  filtered_changes AS fc
LEFT JOIN
  datalake_hubspot.owner AS ho
    ON fc.id_hubspot_owner = ho.id_owner
LEFT JOIN
  datalake_person.person_sks AS ps
    ON ho.uuid_person = ps.uuid_person