WITH extract AS (
    SELECT
        EXPLODE(FROM_JSON(GET_JSON_OBJECT(aud.payload, "$.object.validations"), 'ARRAY<STRING>')) AS validations,
        LOWER(aud.status) AS final_status,
        LOWER(aud.result) AS final_result,
        GET_JSON_OBJECT(aud.payload, "$.object.current_step_type") AS current_step_type,
        GET_JSON_OBJECT(aud.payload, "$.object.failure_status") AS failure_type,
        GET_JSON_OBJECT(aud.payload, "$.object.declined_reason") AS failure_reason,
        rev.ts_created AS ts_report,
        rev.year,
        rev.month,
        rev.day
    FROM
        datalake_arquivo_confidencial_clean.truora_check_process_aud AS aud
    JOIN
        datalake_arquivo_confidencial_clean.rev_info AS rev
            ON rev.rev = aud.rev
    WHERE
        MAKE_DATE(rev.year, rev.month, rev.day) BETWEEN '{load_start_date}' AND '{load_end_date}'
)
SELECT
    GET_JSON_OBJECT(validations, "$.account_id") AS id_account,
    GET_JSON_OBJECT(validations, "$.validation_id") AS id_validation,
    GET_JSON_OBJECT(validations, "$.type") AS validation_type,
    GET_JSON_OBJECT(validations, "$.validation_status") AS validation_status,
    current_step_type,
    failure_type,
    failure_reason,
    final_status,
    final_result,
    ts_report,
    year,
    month,
    day
FROM
    extract
