WITH owner_changes AS (
  SELECT
    ch.id_company,
    ch.id_hubspot_owner,
    ch.ts_updated,
    LAG(ch.id_hubspot_owner) OVER (PARTITION BY ch.id_company ORDER BY ch.ts_updated) AS prev_owner,
    LAG(ch.ts_updated) OVER (PARTITION BY ch.id_company ORDER BY ch.ts_updated) AS prev_ts_updated
  FROM
    datalake_hubspot.company_history AS ch
  WHERE
    ch.id_hubspot_owner IS NOT NULL
),
owner_cochorts AS (
  SELECT
    cc.id_company,
    cc.id_hubspot_owner,
    cc.ts_updated AS ts_start,
    LEAD(cc.ts_updated) OVER (PARTITION BY cc.id_company ORDER BY cc.ts_updated ASC) AS ts_end
  FROM
    owner_changes AS cc
  WHERE
    cc.id_hubspot_owner != prev_owner
    OR cc.prev_owner IS NULL
)
SELECT
  CONCAT(ch.id_company, DATE_FORMAT(ch.ts_start, 'yyyyMMddHHmmss')) AS id_owner_update,
  ch.id_company AS id_hubspot,
  am.uuid_person,
  ch.ts_end IS NULL AS is_current_cohort,
  ch.ts_start,
  ch.ts_end
FROM
  owner_cochorts AS ch
LEFT JOIN
  datalake_hubspot.owner AS am
    ON am.id_owner = ch.id_hubspot_owner
