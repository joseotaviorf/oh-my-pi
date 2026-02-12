SELECT
  id_unidade AS id_unit,
  id_idactum,
  NULLIF(TRIM(nome), '') AS owner_name,
  NULLIF(TRIM(contribuinte_ajustado), '') AS owner_adjusted_name,
  NULLIF(TRIM(documento), '') AS owner_document_number,
  cidade AS city,
  radical AS city_radical,
  origem AS data_source,
  valido AS is_valid,
  data_consulta AS ts_query,
  data_referencia AS ts_reference,
  dt_load
FROM
  datalake_idactum_owners_raw.idactum_owners
