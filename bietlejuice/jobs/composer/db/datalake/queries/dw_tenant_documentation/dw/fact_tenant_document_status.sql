WITH documents AS(
  SELECT /*+ RANGE_JOIN(pd, 10000) */ DISTINCT
    pd.id AS id_document,
    pd.id_proponent,
    pp.id_proposal,
    pd.type,
    pd.ts_created
  FROM 
    datalake_ebdb_clean.proposal_document AS pd
  LEFT JOIN 
    datalake_ebdb_clean.proponent_proposal AS pp
      ON pd.id_proponent = pp.id
),
resend_documents AS (
   SELECT
    pirr_aud.id_proposal_document AS id_document,
    pirr_aud.id_proponent_proposal AS id_proponent,
    pp.id_proposal,
    FROM_UNIXTIME(ure.ts_revision/1000) AS ts_resend,
    pirr_aud.resend_document_reason,
    pirr_aud.proponent_info_type AS document_type,
    pp.type,
    DENSE_RANK() OVER (PARTITION BY pirr_aud.proponent_info_type, pirr_aud.id_proponent_proposal ORDER BY pirr_aud.rev) AS resend_rank
  FROM 
    datalake_ebdb_clean.proponent_info_resend_request_aud AS pirr_aud
  LEFT JOIN 
    datalake_ebdb_clean.proponent_proposal AS pp
      ON pirr_aud.id_proponent_proposal = pp.id
  LEFT JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure 
      ON pirr_aud.rev = ure.id
),
resend_documents_ts AS (
  select
    rd.id_document,
    rd.id_proponent,
    rd.id_proposal,
    rd.resend_document_reason,
    rd.document_type,
    rd.type,
    rd.resend_rank,
    rd.ts_resend,
    LAG(rd.ts_resend, 1) OVER (PARTITION BY rd.document_type, rd.id_proponent ORDER BY rd.ts_resend) AS ts_previous_resend,
    LEAD(rd.ts_resend, 1) OVER (PARTITION BY rd.document_type, rd.id_proponent ORDER BY rd.ts_resend) AS ts_next_resend
  FROM 
    resend_documents AS rd
),
proposal_status AS (
  SELECT /*+ RANGE_JOIN(aud, 100000) */
    aud.id_proposal,
    pp.id AS id_proponent,
    aud.tenant_documentation_status AS status,
    pp.type,
    rev,
    LAG(aud.rev, 1) OVER (PARTITION BY aud.id_proposal ORDER BY aud.rev) AS rev_previous_status,
    LEAD(aud.rev, 1) OVER (PARTITION BY aud.id_proposal ORDER BY aud.rev) AS rev_end_status
  FROM
    datalake_ebdb_clean.proposal_aud AS aud
  LEFT JOIN
    datalake_ebdb_clean.proponent_proposal AS pp
      ON aud.id_proposal = pp.id_proposal
  WHERE 
    aud.mod_tenant_documentation_status = True
),
proposal_status_ts AS (
  SELECT
    ps.id_proposal,
    ps.id_proponent,
    ps.status,
    ps.type,
    FROM_UNIXTIME(ure.ts_revision/1000) AS ts_start_status,
    FROM_UNIXTIME(ure_previous.ts_revision/1000) AS ts_previous_status,
    FROM_UNIXTIME(ure_end.ts_revision/1000) AS ts_end_status
  FROM 
    proposal_status AS ps
  LEFT JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure
      ON ps.rev = ure.id
  LEFT JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure_previous
      ON ps.rev_previous_status = ure_previous.id
  LEFT JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure_end
      ON ps.rev_end_status = ure_end.id
),
resend_data AS (
  SELECT DISTINCT
    rdt.id_document AS sk_document,
    rdt.id_proponent AS sk_proponent,
    rdt.id_proposal AS sk_proposal,
    CAST(date_format(rdt.ts_resend, 'yyyyMMdd') AS INTEGER) AS sk_document_status_date,
    rdt.document_type,
    ps.status,
    rdt.resend_document_reason,
    rdt.resend_rank,
    rdt.ts_resend AS ts_document_status
  FROM 
    resend_documents_ts AS rdt
  LEFT JOIN 
    proposal_status_ts AS ps
      ON ps.id_proponent = rdt.id_proponent
      AND rdt.ts_resend = ps.ts_start_status
      AND ps.status = 'ReenvioDocumentos'
  WHERE 
    rdt.type = 'Inquilino'
),
not_resend_data AS (
  SELECT /*+ RANGE_JOIN(ps, 10000) */ DISTINCT
    d.id_document,
    ps.id_proponent,
    ps.id_proposal,
    d.type AS document_type,
    ps.status,
    CAST(date_format(ps.ts_start_status, 'yyyyMMdd') AS INTEGER) AS ts_document_status_date,
    ps.ts_start_status AS ts_document_status
  FROM 
    proposal_status_ts AS ps
  LEFT JOIN 
    documents d
      ON ps.id_proponent = d.id_proponent
      AND ps.status != 'ReenvioDocumentos'
  WHERE 
    ps.type = 'Inquilino'
),
final_not_resend_data AS (
  SELECT 
    nrd.id_document AS sk_document,
    nrd.id_proponent AS sk_proponent,
    nrd.id_proposal AS sk_proposal,
    nrd.ts_document_status_date AS sk_document_status_date,
    nrd.document_type,
    nrd.status,
    NULL AS resend_document_reason,
    rdt.resend_rank,
    nrd.ts_document_status
  FROM 
    not_resend_data AS nrd
  LEFT JOIN 
    resend_documents_ts AS rdt
      ON nrd.id_document = rdt.id_document
      AND nrd.ts_document_status >= rdt.ts_resend
      AND nrd.ts_document_status < rdt.ts_next_resend
),
tenant_documentation_status AS (
  SELECT * 
  FROM resend_data
  UNION ALL
  SELECT * 
  FROM final_not_resend_data
)

SELECT
  sk_document,
  sk_proponent,
  sk_proposal,
  sk_document_status_date,
  document_type,
  status,
  resend_document_reason,
  CAST(resend_rank AS INTEGER) AS resend_rank,
  DATEDIFF(ts_document_status, LAG(ts_document_status, 1) OVER (PARTITION BY sk_document ORDER BY ts_document_status)) AS days_between_current_and_last_doc_status,
  TIMESTAMP(ts_document_status) AS ts_document_status,
  NOW() AS ts_load
FROM 
  tenant_documentation_status