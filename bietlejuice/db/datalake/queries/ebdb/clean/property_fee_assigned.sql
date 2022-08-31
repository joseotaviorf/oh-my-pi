SELECT
  id,
  contract_id AS id_contract,
  imovel_id AS id_house,
  propertyfee_id AS id_property_fee,
  criadoEm AS ts_created,
  atualizadoEm AS ts_updated
FROM
  datalake_ebdb_raw.propertyfeeassigned