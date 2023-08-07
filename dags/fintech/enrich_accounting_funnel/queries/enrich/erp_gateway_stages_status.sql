SELECT 
  f.id_feature,
  s.hash,
  f.id_source,
  f.id_finance_entity,
  s.id_sync_sap_job,
  f.source as feature_source,
  s.type as sync_sap_job_type,
  f.sync_sap_status, 
  s.status as sync_sap_job_status,
  DATE(f.ts_created) as dt_feature_created,
  DATE(s.ts_created) as dt_sync_sap_job_created,
  DATE(s.ts_synced) as dt_sync_sap_job_synced
FROM
  datalake_sap_gateway.feature f
LEFT JOIN
  datalake_sap_gateway.sync_sap_job s
    on f.id_feature = s.id_feature 
WHERE
  (
    type != 'PN' OR 
    type IS NULL
  )