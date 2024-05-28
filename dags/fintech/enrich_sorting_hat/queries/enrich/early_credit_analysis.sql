WITH base AS (
SELECT 
    id,
    id_credit_evaluation,
    id_user,
    id_house,
    id_variant,
    city,
    version,
    risk_category_canon,
    ts_created,
    ts_expired,
    EXPLODE(FROM_JSON(result,'ARRAY<STRING>')) AS extract_json
FROM 
    datalake_sorting_hat_clean.early_credit_analysis
),
base_json AS (
SELECT 
    id AS id_early_credit,
    id_credit_evaluation,
    id_user,
    id_house,
    id_variant,
    GET_JSON_OBJECT(extract_json, '$.policy_report_id') AS id_policy_report,
    city,
    version,
    risk_category_canon,
    GET_JSON_OBJECT(extract_json, '$.bypass') AS bypass,
    GET_JSON_OBJECT(extract_json, '$.result') AS guarantee_offered,
    GET_JSON_OBJECT(extract_json, '$.category') AS category,
    GET_JSON_OBJECT(extract_json, '$.range_end') AS range_end,
    GET_JSON_OBJECT(extract_json, '$.range_start') AS range_start,
    GET_JSON_OBJECT(extract_json, '$.rejection_reason') AS rejection_reason,
    ts_created,
    ts_expired
FROM 
    base
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_created DESC) = 1
)
SELECT
    id_early_credit,
    id_credit_evaluation,
    id_user,
    id_house,
    id_variant,
    id_policy_report
    city,
    version,
    risk_category_canon,
    bypass,
    guarantee_offered,
    category,
    range_end,
    range_start,
    rejection_reason,
    ROW_NUMBER() OVER ( PARTITION BY id_user, id_house ORDER BY ts_created DESC ) AS early_credit_number,
    IF(early_credit_number = 1, TRUE, FALSE) as is_last_early_credit,
    ts_created,
    ts_expired
FROM
    base_json

