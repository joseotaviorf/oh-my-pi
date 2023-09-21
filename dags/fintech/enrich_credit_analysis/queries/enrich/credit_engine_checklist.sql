WITH latest_checklist_decision AS (
  SELECT
    id_checklist,
    type AS checklist_decision_type,
    decision AS checklist_decision,
    MAX(ts_updated) AS ts_checklist_decision
FROM
  datalake_sorting_hat_clean.checklist_decision
GROUP BY
  id_checklist,
  type,
  decision
)

SELECT DISTINCT
  c.id AS id_checklist,
  c.id_analysis_request,
  cg.id AS id_checklist_group,
  cg.id_subject,
  ci.id AS id_checklist_item,
  ci.id_input_source,
  c.type AS checklist_type,
  cd.checklist_decision_type,
  c.status AS checklist_status,
  cg.status AS checklist_group_status,
  cg.subject_type AS checklist_group_subject_type,
  ci.input_description,
  ci.input_type,
  ci.input_value,
  ci.type AS checklist_item_type,
  c.is_current_checklist,
  cg.is_compliant AS is_checklist_group_compliant,
  ci.is_compliant AS is_checklist_item_compliant,
  cd.checklist_decision,
  c.ts_created AS ts_checklist_created,
  ci.ts_updated AS ts_checklist_updated,
  cd.ts_checklist_decision
FROM
    datalake_sorting_hat_clean.checklist AS c
LEFT JOIN
  datalake_sorting_hat_clean.checklist_group AS cg
    ON cg.id_checklist = c.id
LEFT JOIN
  datalake_sorting_hat_clean.checklist_item AS ci
    ON ci.id_checklist_group = cg.id
LEFT JOIN
  latest_checklist_decision AS cd
    ON cd.id_checklist = c.id