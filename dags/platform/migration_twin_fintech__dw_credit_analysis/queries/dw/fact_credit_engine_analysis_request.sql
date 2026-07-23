WITH analysis_request_latest_update AS (
  SELECT
    id_analysis_request,
    MAX(ts_analysis_request_updated) AS ts_analysis_request_last_update
  FROM
    datalake_credit_analysis.credit_engine_analysis_request
  GROUP BY id_analysis_request
)

SELECT DISTINCT
  c.id_checklist_item AS sk_checklist_item,
  c.id_checklist AS sk_checklist,
  c.id_checklist_group AS sk_checklist_group,
  CAST(c.id_input_source AS INTEGER) AS sk_input_source,
  ar.id_analysis_request AS sk_analysis_request,
  CAST(ar.id_proposal AS BIGINT) AS sk_proposal,
  c.input_type,
  c.checklist_item_type,
  c.checklist_group_subject_type,
  c.input_value,
  c.input_description,
  c.checklist_decision,
  ar.business_context,
  c.is_checklist_group_compliant,
  c.is_checklist_item_compliant,
  c.is_current_checklist,
  ar.ts_analysis_request_created,
  arlu.ts_analysis_request_last_update,
  NOW() AS ts_load
FROM
  datalake_credit_analysis.credit_engine_checklist AS c
LEFT JOIN
  datalake_credit_analysis.credit_engine_analysis_request AS ar
    ON ar.id_analysis_request = c.id_analysis_request
LEFT JOIN
  analysis_request_latest_update AS arlu
    ON arlu.id_analysis_request = ar.id_analysis_request