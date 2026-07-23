WITH policy_report_extract_json AS (
    SELECT
        id,
        EXPLODE_OUTER(
            FROM_JSON(
                GET_JSON_OBJECT(result, '$.proponents'),
                'ARRAY<
                    STRUCT<
                        document_number: STRING,
                        is_retenant: BOOLEAN,
                        retenant_contract_id: STRING,
                        retenant_contract_proposal_id: STRING,
                        retenant_contract_user_id: STRING,
                        retenant_score: STRING
                    >
                >'
                )
        ) AS extract_json
    FROM
        datalake_sorting_hat_clean.policy_report
),
proponents AS (
  SELECT
    id AS id_policy_evaluation,
    extract_json.retenant_contract_user_id,
    extract_json.retenant_score,
    extract_json.document_number,
    extract_json.is_retenant
  FROM
    policy_report_extract_json
),
retenant_policy_report AS (
  SELECT
    pr.id AS id_policy_evaluation,
    CAST(pr.id_external AS INTEGER) AS id_external,
    pr.type AS policy_name,
    pr.external_source,
    GET_JSON_OBJECT(pr.result, '$.type') AS proponent_group_class,
    GET_JSON_OBJECT(pr.result, '$.subtype') AS proponent_class_detail,
    GET_JSON_OBJECT(pr.result, '$.full_type') AS proponent_group_class_detail,
    pr.version,
    GET_JSON_OBJECT(pr.result, '$.classification') AS retenant_classification,
    CAST(GET_JSON_OBJECT(pr.result, '$.avg_retenant_score') AS DECIMAL(10,2)) AS avg_retenant_score,
    CAST(GET_JSON_OBJECT(pr.result, '$.elected_contract_id') AS INTEGER) AS id_retenant_elected_contract,
    MAX(CAST(proponents.retenant_contract_user_id AS INTEGER)) AS id_retenant_contract_user,
    COUNT(proponents.document_number) AS number_of_proponents,
    AVG(proponents.retenant_score) AS average_retenants_score_calculated,
    CASE
      WHEN GET_JSON_OBJECT(pr.result, '$.type') = 'ANY_PROPONENT' THEN TRUE
      WHEN GET_JSON_OBJECT(pr.result, '$.type') = 'NEW_GROUP_PROPONENT' THEN TRUE
      WHEN GET_JSON_OBJECT(pr.result, '$.type') = 'SAME_GROUP_PROPONENT' THEN TRUE
      WHEN GET_JSON_OBJECT(pr.result, '$.type') = 'NEW_USER' THEN FALSE
      ELSE NULL
    END AS is_retenant,
    CASE
      WHEN COUNT(DISTINCT proponents.is_retenant) = 1
      AND MAX(proponents.is_retenant) = TRUE THEN TRUE
      ELSE FALSE
    END AS are_all_proponents_retenants,
    pr.ts_created,
    pr.ts_updated
  FROM
    datalake_sorting_hat_clean.policy_report AS pr
    LEFT JOIN proponents ON pr.id = proponents.id_policy_evaluation
  WHERE
    pr.type = 'RETENANT'
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    17,
    18
)

SELECT
  id_policy_evaluation,
  id_external,
  id_retenant_elected_contract,
  id_retenant_contract_user,
  policy_name,
  external_source,
  retenant_classification,
  proponent_group_class,
  proponent_class_detail,
  proponent_group_class_detail,
  number_of_proponents,
  COALESCE(avg_retenant_score, average_retenants_score_calculated) AS average_retenants_score,
  version,
  is_retenant,
  are_all_proponents_retenants,
  ts_created,
  ts_updated
FROM
    retenant_policy_report
