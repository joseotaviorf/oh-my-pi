SELECT
  id,
  visita_id AS id_visit,
  REV AS rev,
  REVTYPE AS rev_type,
  reason,
  on_behalf_of,
  visita_id_MOD AS mod_id_visit,
  reason_MOD AS mod_reason,
  on_behalf_of_MOD AS mod_on_behalf_of,
  criadoEm AS ts_created
FROM
  datalake_ebdb_raw.VisitCancellationDetails_AUD
