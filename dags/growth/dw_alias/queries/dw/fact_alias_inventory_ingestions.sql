WITH broker_map AS (
  SELECT DISTINCT
    uuid_company,
    CAST(id AS VARCHAR) AS sk_broker
  FROM datalake_company_clean.company
)
SELECT
  ii.uuid_inventory_ingestion          AS sk_inventory_ingestion,
  bm.sk_broker,
  ii.status,
  ii.status = 'COMPLETED'             AS is_successful,
  ii.quantity_created,
  ii.quantity_updated,
  ii.quantity_failed,
  ii.quantity_skipped,
  ii.quantity_unpublished,
  ii.failure_reason,
  CASE WHEN ii.ts_started IS NOT NULL AND ii.ts_completed IS NOT NULL
    THEN (UNIX_TIMESTAMP(ii.ts_completed) - UNIX_TIMESTAMP(ii.ts_started)) / 60.0
  END                                  AS duration_minutes,
  ii.ts_started,
  ii.ts_completed,
  CURRENT_TIMESTAMP()                  AS ts_load,
  YEAR(ii.ts_started)                  AS year,
  MONTH(ii.ts_started)                 AS month,
  DAY(ii.ts_started)                   AS day
FROM datalake_alias_clean.inventory_ingestions AS ii
LEFT JOIN broker_map AS bm ON ii.uuid_company = bm.uuid_company
WHERE '{load_start_date}' <= ii.ts_updated
  AND ii.ts_updated < '{load_end_date}'
