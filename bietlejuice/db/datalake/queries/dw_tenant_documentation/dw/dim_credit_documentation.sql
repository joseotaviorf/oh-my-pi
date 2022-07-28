WITH documents_proposal AS(
  SELECT
    p.id AS id_proposal,
    p.tenant_documentation_status AS document_status,
    CAST(COLLECT_SET(pd.type) AS STRING) AS documents
  FROM 
    datalake_ebdb_clean.proposal AS p
  LEFT JOIN 
    datalake_ebdb_clean.proposal_document AS pd
      ON p.id_proponent = pd.id_proponent
  GROUP BY
    p.id,
    p.tenant_documentation_status
)
SELECT
  dp.id_proposal AS sk_proposal,
  ce.id AS sk_credit_evaluation,
  dp.documents as documents_needed,
  CASE 
    WHEN dp.document_status <> 'Aprovado' THEN 'NOT APPROVED' 
    ELSE 'APPROVED' 
  END AS documents_status,
  ce.ts_created AS ts_credit_started,
  ce.ts_updated AS ts_credit_updated,
  NOW() AS ts_load
FROM 
  documents_proposal AS dp
LEFT JOIN 
  datalake_docx_clean.credit_evaluation ce
    ON ce.id_proposal = dp.id_proposal
WHERE
  ce.status <> 'NOT SENT'
  