SELECT
  ans.id AS id_analysis_state,
  am.id AS id_machine,
  ar.id AS id_analysis_request,
  asg.id AS id_state_group,
  CAST(ar.id_external AS INT) AS id_proposal,
  ans.subject_type,
  ans.id_subject AS policy_type,
  am.status AS machine_status,
  am.type AS machine_type,
  asg.group_type,
  asg.group_name,
  asg.result AS state_group_result,
  ans.result AS analysis_state_result,
  ans.input,
  ans.status AS analysis_state_status,
  am.is_current_machine,
  ans.ts_updated,
  ans.ts_created
FROM
  datalake_sorting_hat_clean.analysis_state AS ans
INNER JOIN
  datalake_sorting_hat_clean.analysis_state_group AS asg
    ON asg.id = ans.id_state_group
INNER JOIN
  datalake_sorting_hat_clean.analysis_machine AS am
    ON am.id = asg.id_machine
INNER JOIN
  datalake_sorting_hat_clean.analysis_request AS ar
    ON ar.id = am.id_analysis_request
WHERE
  ans.subject_type = 'CHECKLIST_ITEM_TYPE'
