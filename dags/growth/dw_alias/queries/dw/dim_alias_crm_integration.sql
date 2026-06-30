WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
)
SELECT
  aci.uuid_crm_integration                    AS sk_crm_integration,
  bm.sk_broker,
  aci.platform,
  aci.is_active,
  -- Excluded: access_token, client_secret, api_key, webhook_secret (sensitive credentials)
  aci.ts_created,
  aci.ts_updated,
  CURRENT_TIMESTAMP()                         AS ts_load,
  YEAR(aci.ts_updated)                        AS year,
  MONTH(aci.ts_updated)                       AS month,
  DAY(aci.ts_updated)                         AS day
FROM datalake_alias_clean.crm_integrations AS aci
LEFT JOIN broker_map AS bm ON aci.uuid_company = bm.uuid_company
WHERE '{load_start_date}' <= aci.ts_updated
  AND aci.ts_updated < '{load_end_date}'
