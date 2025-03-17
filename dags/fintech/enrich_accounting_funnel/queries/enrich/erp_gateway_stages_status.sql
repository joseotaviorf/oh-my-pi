SELECT
  f.id_source,
  f.id_finance_entity,
  f.id_feature,
  s.id_sync_sap_job,
  s.hash,
  f.source_client,
  f.source as source_type,
  f.user_type,
  f.finance_entity_type,
  f.transaction_type,
  s.type as sync_sap_job_type,
  f.sync_sap_status,
  s.status as sync_sap_job_status,
  CASE
    WHEN f.ts_created IS NOT NULL AND s.ts_created IS NULL AND s.ts_synced IS NULL THEN 'sap job not created'
    WHEN f.ts_created IS NOT NULL AND s.ts_created IS NOT NULL AND s.ts_synced IS NULL THEN 'sap job not synced'
    WHEN f.ts_created IS NOT NULL AND s.ts_created IS NOT NULL AND s.ts_synced IS NOT NULL THEN 'synced'
    END AS stage_status,
  DATE(f.ts_created) as dt_feature_created,
  DATE(s.ts_created) as dt_sync_sap_job_created,
  DATE(s.ts_synced) as dt_sap_job_synced,
  DATE(COALESCE(s.ts_updated, f.ts_updated)) AS dt_updated
FROM
  datalake_sap_gateway_clean.feature f
LEFT JOIN
  datalake_sap_gateway_clean.sync_sap_job s
    on f.id_feature = s.id_feature
WHERE
  (
    type != 'PN' OR
    type IS NULL
  )
AND erp_solution = 'B1'
AND f.ts_created >= '2023-01-01'
