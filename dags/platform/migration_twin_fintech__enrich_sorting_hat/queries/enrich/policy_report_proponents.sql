WITH policy_report_extract_json AS (
SELECT
    id,
    EXPLODE(FROM_JSON(GET_JSON_OBJECT(result, '$.proponents'), 'ARRAY<STRING>')) AS extract_json
FROM
    datalake_sorting_hat_clean.policy_report
),
user (
SELECT
  id AS id_user,
  cpf
FROM
  datalake_ebdb_user.user
QUALIFY --filter to return only the user with the most recent creation date.
  ROW_NUMBER() OVER (PARTITION BY cpf ORDER BY ts_created DESC) = 1
)
SELECT
    policy_report_extract_json.id AS id_policy_evaluation,
    CAST(GET_JSON_OBJECT(extract_json, '$.retenant_contract_id') AS INTEGER) AS id_retenant_contract,
    CAST(GET_JSON_OBJECT(extract_json, '$.retenant_contract_proposal_id') AS INTEGER) AS id_retenant_contract_proposal,
    CAST(GET_JSON_OBJECT(extract_json, '$.retenant_contract_user_id') AS INTEGER) AS id_retenant_contract_user,
    user.id_user,
    CAST(GET_JSON_OBJECT(extract_json, '$.document_number') AS STRING) AS proponent_document_number,
    GET_JSON_OBJECT(extract_json, '$.retenant_score') AS retenant_score,
    GET_JSON_OBJECT(extract_json, '$.is_retenant') AS is_retenant
FROM
    policy_report_extract_json
LEFT JOIN
--join to remove cpf from query
    user ON GET_JSON_OBJECT(extract_json, '$.document_number') = user.cpf
