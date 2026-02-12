SELECT
  id,
  id_transacao AS id_transaction,
  id_idactum,
  NULLIF(TRIM(nome), '') AS buyer_name,
  NULLIF(TRIM(documento), '') AS buyer_document,
  doc_faltante_em_algum_ponto AS is_document_missing_at_some_step,
  dt_load
FROM
  datalake_idactum_buyers_raw.idactum_buyers
