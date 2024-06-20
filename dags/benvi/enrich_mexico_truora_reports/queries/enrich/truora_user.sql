SELECT
    CAST(aud.id_external AS BIGINT) AS id_external,
    GET_JSON_OBJECT(aud.payload, "$.object.account_id") AS id_account,
    GET_JSON_OBJECT(aud.payload, "$.object.rfc") AS rfc,
    GET_JSON_OBJECT(aud.payload, "$.object.document_number") AS curp,
    GET_JSON_OBJECT(aud.payload, "$.object.first_name") AS first_name,
    GET_JSON_OBJECT(aud.payload, "$.object.last_name") AS last_name,
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
