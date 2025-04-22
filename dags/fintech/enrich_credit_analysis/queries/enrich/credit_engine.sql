  SELECT
    ans.id AS id_analysis_state,
    am.id AS id_machine,
    ar.id AS id_analysis_request,
    asg.id AS id_state_group,
    CAST(ar.id_external AS INT) AS id_proposal,
    ans.subject_type,
    IF(ans.subject_type = 'CHECKLIST_ITEM_TYPE', ans.id_subject, NULL) AS policy_type,
    IF(asg.group_name = 'INCOME_DOCUMENT', get_json_object(ans.input, '$.category'), NULL) AS category,
    am.status AS machine_status,
    am.machine_version,
    am.type AS machine_type,
    asg.group_type,
    asg.group_name,
    asg.result AS state_group_result,
    ans.result AS analysis_state_result,
    ans.input,
    IF(asg.group_name IN ('VERIFIED_PAYMENT_CAPABILITY', 'INCOME_DOCUMENT', 'INCOME_VALUE_VERIFIED', 'INCOME_DOCUMENT_OPTIONAL'), get_json_object(ans.input, '$.documentation_analysis_type'), NULL) AS documentation_analysis_type,
    IF(asg.group_name = 'VERIFIED_PAYMENT_CAPABILITY', get_json_object(ans.input, '$.package_value'), NULL) AS package_value,
    IF(asg.group_name = 'VERIFIED_PAYMENT_CAPABILITY', get_json_object(ans.input, '$.total_verified_income'), NULL) AS total_verified_income,
    IF(asg.group_name = 'VERIFIED_PAYMENT_CAPABILITY', get_json_object(ans.input, '$.total_compromised_income'), NULL) AS total_compromised_income,
    IF(asg.group_name = 'NUMBER_OF_RESENDS', get_json_object(ans.input, '$.number_of_resend_requests'), NULL) AS number_of_resend_requests,
    IF(asg.group_name = 'ACTIVE_CONTRACT', get_json_object(ans.input, '$.active_contracts'), NULL) AS active_contracts,
    IF(asg.group_name = 'LEGAL_AGE', get_json_object(ans.input, '$.age'), NULL) AS tenant_age,
    IF(asg.group_name IN ('LAWSUIT', 'BLOCKLIST', 'BUREAU', 'SELFIE'), get_json_object(ans.input, '$.score'), NULL) AS score,
    IF(asg.group_name IN ('INCOME_DOCUMENT', 'VERIFIED_PAYMENT_CAPABILITY'), get_json_object(ans.input, '$.income_value_verified_state_result'), NULL) AS income_value_verified_state_result,
    ans.status AS analysis_state_status,
    am.is_current_machine,
    IF(asg.group_name = 'VERIFIED_PAYMENT_CAPABILITY', get_json_object(ans.input, '$.is_there_empty_verified_income'), NULL) AS is_there_empty_verified_income,
    IF(asg.group_name = 'POLITICALLY_EXPOSED_PERSON', get_json_object(ans.input, '$.is_currently_pep'), NULL) AS is_currently_pep,
    IF(asg.group_name IN ('INCOME_DOCUMENT', 'VERIFIED_PAYMENT_CAPABILITY'), get_json_object(ans.input, '$.is_income_sufficient_for_renting'), NULL) AS is_income_sufficient_for_renting,
    IF(asg.group_name = 'INCOME_VALUE_VERIFIED', get_json_object(ans.input, '$.is_there_any_fraud_suspicion'), NULL) AS is_there_any_fraud_suspicion,
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
    ans.subject_type IN ('CHECKLIST_ITEM_TYPE', 'TENANT', 'PROPOSAL')
