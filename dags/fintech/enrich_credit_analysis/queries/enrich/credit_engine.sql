WITH get_analysis_state_data AS (
SELECT
    ans.id AS id_analysis_state,
    am.id AS id_machine,
    ar.id AS id_analysis_request,
    asg.id AS id_state_group,
    IF(ar.external_source = 'PROPOSAL', ar.id_external, NULL) AS id_proposal,
    IF(
      ar.external_source = 'CREDIT_EVALUATION', ar.id_external, NULL
    ) AS id_credit_evaluation,
    ans.subject_type,
    IF(ans.subject_type = 'CHECKLIST_ITEM_TYPE', ans.id_subject, NULL) AS policy_type,
    IF(
      asg.group_name IN ('INCOME_DOCUMENT', 'INCOME_VALUE_VERIFIED', 'CREDIT_POLICY'),
      COALESCE(
        get_json_object(ans.input, '$.category'), get_json_object(ans.input, '$.analysis_category')
      ),
      NULL
    ) AS category,
    am.status AS machine_status,
    am.machine_version,
    am.type AS machine_type,
    asg.group_type,
    asg.group_name,
    ar.result AS analysis_request_result,
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
    IF(
      asg.group_name = 'PRE_APPROVAL_LIMIT_POLICY', get_json_object(ans.input, '$.debit_limit'), NULL
    ) AS debit_limit,
    IF(
      asg.group_name = 'PRE_APPROVAL_LIMIT_POLICY',
      get_json_object(ans.input, '$.pre_approval_limit'),
      NULL
    ) AS pre_approval_limit,
    IF(
      asg.group_name IN ('PRE_APPROVAL_LIMIT_POLICY', 'CREDIT_POLICY'),
      get_json_object(ans.input, '$.total_informed_income'),
      NULL
    ) AS total_informed_income,
    IF(asg.group_name IN ('CREDIT_POLICY', 'INCOME_VALUE_VERIFIED'), get_json_object(ans.input, '$.risk_category_canon'), NULL) AS risk_category_canon,
    IF(asg.group_name = 'CREDIT_POLICY', get_json_object(ans.input, '$.dti'), NULL) AS dti,
    IF(
      asg.group_name = 'CREDIT_POLICY', get_json_object(ans.input, '$.policy_dti'), NULL
    ) AS policy_dti,
    am.is_current_machine,
    IF(asg.group_name = 'VERIFIED_PAYMENT_CAPABILITY', get_json_object(ans.input, '$.is_there_empty_verified_income'), NULL) AS is_there_empty_verified_income,
    IF(asg.group_name = 'POLITICALLY_EXPOSED_PERSON', get_json_object(ans.input, '$.is_currently_pep'), NULL) AS is_currently_pep,
    IF(asg.group_name IN ('INCOME_DOCUMENT', 'VERIFIED_PAYMENT_CAPABILITY'), get_json_object(ans.input, '$.is_income_sufficient_for_renting'), NULL) AS is_income_sufficient_for_renting,
    IF(asg.group_name = 'INCOME_VALUE_VERIFIED', get_json_object(ans.input, '$.is_there_any_fraud_suspicion'), NULL) AS is_there_any_fraud_suspicion,
    IF(asg.group_name = 'INCOME_VALUE_VERIFIED', get_json_object(ans.input, '$.is_low_risk'), NULL) AS is_low_risk,
    IF(asg.group_name = 'VERIFIED_PAYMENT_CAPABILITY', get_json_object(ans.input, '$.is_verification_skipped'), NULL) AS is_verification_skipped,
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
    ans.subject_type IN ('CHECKLIST_ITEM_TYPE', 'TENANT', 'PROPOSAL', 'CREDIT_EVALUATION')
)
SELECT
    CAST(id_analysis_state AS INT) AS id_analysis_state,
    CAST(id_machine AS INT) AS id_machine,
    CAST(id_analysis_request AS INT) AS id_analysis_request,
    CAST(id_state_group AS INT) AS id_state_group,
    CAST(id_proposal AS INT) AS id_proposal,
    CAST(id_credit_evaluation AS INT) AS id_credit_evaluation,
    subject_type,
    policy_type,
    CAST(category AS INT) AS category,
    risk_category_canon,
    machine_status,
    machine_version,
    machine_type,
    group_type,
    group_name,
    state_group_result,
    analysis_state_result,
    analysis_request_result,
    input,
    documentation_analysis_type,
    CAST(package_value AS DECIMAL(10,2)) AS package_value,
    CAST(total_verified_income AS DECIMAL(10,2)) AS total_verified_income,
    CAST(total_compromised_income AS DECIMAL(10,2)) AS total_compromised_income,
    CAST(total_informed_income AS DECIMAL(10,2)) AS total_informed_income,
    CAST(number_of_resend_requests AS INT) AS number_of_resend_requests,
    CAST(active_contracts AS INT) AS number_of_active_contracts,
    CAST(tenant_age AS INT) AS tenant_age,
    CAST(score AS DECIMAL(10,2)) AS score,
    income_value_verified_state_result,
    analysis_state_status,
    CAST(debit_limit AS DECIMAL(10,2)) AS debit_limit,
    CAST(pre_approval_limit AS DECIMAL(10,2)) AS pre_approval_limit,
    CAST(dti AS DECIMAL(10,2)) AS dti,
    policy_dti,
    CAST(is_current_machine AS BOOLEAN) AS is_current_machine,
    CAST(is_there_empty_verified_income AS BOOLEAN) AS is_there_empty_verified_income,
    CAST(is_currently_pep AS BOOLEAN) AS is_currently_pep,
    CAST(is_income_sufficient_for_renting AS BOOLEAN) AS is_income_sufficient_for_renting,
    CAST(is_there_any_fraud_suspicion AS BOOLEAN) AS is_there_any_fraud_suspicion,
    CAST(is_low_risk AS BOOLEAN) AS is_low_risk,
    CAST(is_verification_skipped AS BOOLEAN) AS is_verification_skipped,
    ts_updated,
    ts_created
FROM get_analysis_state_data
