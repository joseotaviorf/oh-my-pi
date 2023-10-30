SELECT
  id,
  visita_id AS id_visit,
  reason,
  on_behalf_of,
  criadoEm AS ts_created,
  atualizadoEm AS ts_updated
FROM
  datalake_ebdb_raw.VisitCancellationDetails