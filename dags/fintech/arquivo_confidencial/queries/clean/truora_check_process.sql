SELECT
    id,
    process_id AS id_process,
    external_id AS id_external,
    api_key,
    document_value,
    status,
    result,
    payload,
    version,
    expiration_date AS ts_expiration,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.truora_check_process
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
