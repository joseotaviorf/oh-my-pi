SELECT
  DISTINCT am.id AS id_machine,
  am.id_analysis_request,
  am.id_subject,
  asg.id AS id_state_group,
  am.subject_type,
  am.status AS machine_status,
  am.type AS machine_type,
  am.is_current_machine,
  asg.group_type,
  asg.group_name,
  asg.result AS state_group_result,
  as.input,
  as.status AS analysis_state_status,
  asg.ts_updated,
  am.ts_created
FROM
  datalake_sorting_hat_clean.analysis_machine AS am
LEFT JOIN
  datalake_sorting_hat_clean.analysis_state_group AS asg
    ON asg.id_machine = am.id
LEFT JOIN
  datalake_sorting_hat_clean.analysis_state AS as 
    ON as.id_state_group = asg.id