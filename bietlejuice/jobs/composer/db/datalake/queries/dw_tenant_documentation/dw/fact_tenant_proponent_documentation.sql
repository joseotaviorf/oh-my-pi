WITH documents_resent AS(
  SELECT
    id_proponent_proposal,
    COUNT(id) AS amount_documents_resent,
    MIN(ts_created) AS ts_first_document_resent,
    MAX(ts_created) AS ts_last_document_resent
  FROM 
    datalake_ebdb_clean.proponent_info_resend_request
  GROUP BY
    id_proponent_proposal
),
documents_sent AS(
  SELECT
    id_proponent,
    COUNT(DISTINCT type) AS amount_documents_needed,
    COUNT(id) AS amount_documents_sent,
    MIN(ts_created) AS ts_first_documents_sent
  FROM 
    datalake_ebdb_clean.proposal_document
  GROUP BY
    id_proponent
)
SELECT
  pp.id AS sk_proponent,
  pp.id_proposal AS sk_proposal,
  CAST(DATE_FORMAT(ds.ts_first_documents_sent, 'yyyyMMdd') AS BIGINT) AS sk_first_document_sent_date,
  CAST(DATE_FORMAT(dr.ts_first_document_resent, 'yyyyMMdd') AS BIGINT) AS sk_first_document_resent_date,
  CAST(DATE_FORMAT(dr.ts_last_document_resent, 'yyyyMMdd') AS BIGINT) AS sk_last_document_resent_date,
  CAST(ds.amount_documents_needed AS INTEGER) AS amount_documents_needed,
  CAST(ds.amount_documents_sent + COALESCE(dr.amount_documents_resent, 0) AS INTEGER) AS amount_documents_sent,
  dr.amount_documents_resent IS NULL AS is_resent,
  ds.ts_first_documents_sent,
  dr.ts_first_document_resent,
  dr.ts_last_document_resent,
  NOW() AS ts_load
FROM 
  datalake_ebdb_clean.proponent_proposal AS pp
INNER JOIN
  documents_sent AS ds
    ON pp.id = ds.id_proponent
LEFT JOIN
  documents_resent AS dr
    ON pp.id = dr.id_proponent_proposal
WHERE 
  pp.type = 'Inquilino'
  