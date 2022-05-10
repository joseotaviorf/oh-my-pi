SELECT
    id,
    external_id AS id_external,
    process_id AS id_process,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    external_source,
    GET_JSON_OBJECT(attributes, '$.liveness') AS liveness,
    GET_JSON_OBJECT(attributes, '$.faceMatch') AS face_match,
    GET_JSON_OBJECT(attributes, '$.status') AS status,
    GET_JSON_OBJECT(attributes, '$.score') AS score,
    GET_JSON_OBJECT(attributes, '$.hasBiometry') AS has_biometry,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.unico_check_process_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}