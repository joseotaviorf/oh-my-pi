SELECT
  id,
  item_id AS id_item,
  refId as id_ref,
  checklistItem AS checklist_item,
  nome AS name,
  tipo AS type,
  criadoEm AS ts_created,
  atualizadoEm AS ts_updated
FROM
  datalake_ebdb_test_raw.fotoitemvistoria
