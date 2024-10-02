SELECT
  id,
  visita_id AS id_visit,
  visit_status_log_id AS id_visit_status_log,
  reason,
  on_behalf_of,
  channel,
  criadoEm AS ts_created,
  atualizadoEm AS ts_updated
FROM
  datalake_ebdb_test_raw.VisitCancellationDetails
