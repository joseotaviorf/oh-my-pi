WITH exploding_json AS (
    SELECT
        id,
        id_credit_evaluation,
        id_user,
        id_house,
        id_variant,
        city,
        EXPLODE(FROM_JSON(result, 'ARRAY<STRING>')) AS result,
        version,
        ts_created,
        ts_expired
    FROM
        datalake_sorting_hat_clean.early_credit_analysis
)
SELECT
    id,
    id_credit_evaluation,
    id_user,
    id_house,
    id_variant,
    GET_JSON_OBJECT(result, '$.model_variant_id') AS id_model_variant,
    city,
    GET_JSON_OBJECT(result, '$.score') AS score,
    GET_JSON_OBJECT(result, '$.bypass') AS bypass,
    NULLIF(REPLACE(REPLACE(GET_JSON_OBJECT(result, '$.errors'), '[', ''), ']', ''), '') AS errors,
    GET_JSON_OBJECT(result, '$.result') AS result,
    GET_JSON_OBJECT(result, '$.category') AS category,
    GET_JSON_OBJECT(result, '$.range_start') AS range_start,
    GET_JSON_OBJECT(result, '$.range_end') AS range_end,
    GET_JSON_OBJECT(result, '$.model_variant') AS model_variant,
    GET_JSON_OBJECT(result, '$.risk_category') AS risk_category,
    GET_JSON_OBJECT(result, '$.rejection_reason') AS rejection_reason,
    version,
    ts_created,
    ts_expired
FROM
    exploding_json