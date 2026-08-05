SELECT
  id,
  id_transacao AS id_transaction,
  id_idactum,
  NULLIF(TRIM(nome), '') AS buyer_name,
  NULLIF(TRIM(documento), '') AS buyer_document,
  CAST(NULL AS BOOLEAN) AS is_document_missing_at_some_step, -- dropped from source in the 2026-07-23 iDactum dump
  dt_load
FROM
  datalake_idactum_buyers_raw.idactum_buyers
WHERE
  id IS NOT NULL
