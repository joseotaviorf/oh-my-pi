SELECT
  id,
  contract_id AS id_contract,
  imovel_id AS id_house,
  propertyfee_id AS id_property_fee,
  rev,
  revtype as rev_type
FROM
  datalake_ebdb_raw.propertyfeeassigned_aud