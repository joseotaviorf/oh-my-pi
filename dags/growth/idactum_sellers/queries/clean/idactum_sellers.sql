SELECT
  id_idactum,
  id_transacao AS id_transaction,
  NULLIF(TRIM(nome), '') AS seller_name,
  NULLIF(TRIM(documento), '') AS seller_document_number,
  data_transacao AS ts_transaction,
  dt_load
FROM
  datalake_idactum_sellers_raw.idactum_sellers
