WITH credit_evaluation AS (
  -- following columns shouldn't differ among the same proposal
  -- however, if they do, we will get the most recent one
  SELECT DISTINCT
    id_proposal,
    ce.ts_proposal_first_credit_evaluation_positive,
    ce.ts_proposal_last_credit_evaluation_positive,
    ce.proposal_last_result,
    ce.proposal_number_evaluations,
    row_number() over (
      partition BY id_proposal ORDER BY ts_updated DESC, ts_created DESC
    ) AS proposal_credit_evaluation_row_number
  FROM
    datalake_docx.credit_evaluation ce
),
sorting_hat_proposal AS (
  select
    p.id,
    p.status,
    row_number() over (
    -- TODO [ODS] Check if it makes sense to shift to last version instead of first
      partition BY p.id ORDER BY pv.id
    ) AS proposal_version_row_number
  FROM datalake_sorting_hat_clean.proposal p
	LEFT JOIN datalake_sorting_hat_clean.proposal_version pv
		ON p.id = pv.id_proposal
),
dti AS (
    SELECT
        p.id AS id_proposal,
        NULLIF(SUM(p2.monthly_income),0) AS income,
        MAX(p.rent_value + COALESCE(p.condo_value,0) + COALESCE(p.iptu_value,0) + COALESCE(p.home_insurance_value,0)) AS package,
        CASE 
            WHEN SUM(p2.monthly_income) != 0 THEN CAST(MAX(p.rent_value + COALESCE(p.condo_value,0) + COALESCE(p.iptu_value,0) + COALESCE(p.home_insurance_value,0))/SUM(p2.monthly_income) AS DECIMAL(9,2))
            ELSE NULL 
        END AS dti
    FROM
        datalake_sorting_hat_clean.proposal p 
    LEFT JOIN 
        datalake_sorting_hat_clean.proponent p2 
            ON p.id = p2.id_proposal 
    GROUP BY 1
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  CAST(p.id AS INTEGER) AS sk_proposal,
  CAST(p.id AS INTEGER) AS id_proposal,
  p.guarantee,
  p.status,
  p.tenant_documentation_status AS status_doc_tenant,
  p.owner_documentation_status AS status_doc_owner,
  p.rejection_reason,
  ce.proposal_last_result AS result_credit_evaluation,
  NULLIF(sh.status, '') AS status_sortinghat,
  d.dti,
  CAST(d.income AS INTEGER) AS monthly_income_declared,
  CAST(d.package AS INTEGER) AS package_amount,
  p.rent_proposal AS renting_proposal_value,
  CAST(p.tenant_doc_sent_count AS INTEGER) AS tenant_document_sent_count,
  CAST(ce.proposal_number_evaluations AS INTEGER) AS credit_evaluation_count,
  CAST(p.has_tenant_sent_documentation AS INTEGER) AS tenant_document_sent,
  CAST(p.has_tenant_accepted_contract AS INTEGER) AS tenant_contract_accepted,
  CAST(p.has_owner_accepted_contract AS INTEGER) owner_contract_accepted,
  CAST(p.has_owner_sent_documentation AS INTEGER) AS owner_document_sent,
  CAST(p.is_doc_reused AS INTEGER) AS flg_doc_reused,
  p.ts_proposal AS dt_proposal,
  p.ts_approved AS dt_proposal_approved,
  p.ts_processed,
  p.ts_created AS dt_created,
  p.ts_updated AS dt_updated,
  p.ts_documentation_sent AS dt_tenant_document_sent,
  p.ts_owner_documentation_sent AS dt_owner_document_sent,
  date_trunc('day', p.ts_tenant_first_doc_sent) AS dt_tenant_first_document_sent,
  p.ts_tenant_auto_first_doc_sent AS dt_tenant_auto_first_doc_sent,
  p.ts_credit_analysis_first_init AS dt_credit_analysis_first_init,
  p.ts_credit_analysis_last_init AS dt_credit_analysis_init,
  p.ts_credit_analysis_first_end AS dt_credit_analysis_first_end,
  p.ts_credit_analysis_last_end AS dt_credit_analysis_end,
  p.ts_credit_approved_last AS dt_credit_last_approved,
  p.ts_tenant_first_doc_complete AS dt_tenant_first_doc_complete,
  p.ts_tenant_last_doc_complete AS dt_tenant_last_doc_complete,
  p.ts_credit_evaluation_first_init AS dt_first_credit_evaluation_init,
  p.ts_credit_evaluation_last_init AS dt_last_credit_evaluation_init,
  p.ts_credit_evaluation_first_negative AS dt_first_credit_evaluation_negative,
  p.ts_credit_evaluation_last_negative AS dt_last_credit_evaluation_negative,
  p.ts_guarantee AS dt_guarantee,
  p.ts_doc_analysis_first_approved AS dt_first_doc_analysis_approved,
  p.ts_doc_analysis_last_approved AS dt_last_doc_analysis_approved,
  p.ts_doc_analysis_first_rejected AS dt_first_doc_analysis_rejected,
  p.ts_doc_analysis_last_rejected AS dt_last_doc_analysis_rejected,
  p.ts_guarantee_paid AS dt_guarantee_paid,
  ce.ts_proposal_first_credit_evaluation_positive AS dt_first_credit_evaluation_positive,
  ce.ts_proposal_last_credit_evaluation_positive AS dt_last_credit_evaluation_positive,
  p.dt_credit_analysis_last_init,
  p.dt_credit_analysis_last_end,
  p.ts_tenant_last_doc_complete AS dt_tenant_doc_complete,
  now() AS dt_timestamp,
  now() AS ts_load
FROM datalake_proposal.proposal p
LEFT JOIN credit_evaluation ce
  ON ce.proposal_credit_evaluation_row_number = 1
     AND p.id = ce.id_proposal
LEFT JOIN sorting_hat_proposal sh
  ON sh.proposal_version_row_number = 1
     AND sh.id = p.id
LEFT JOIN 
  dti AS d
    ON d.id_proposal = p.id