SELECT
    id,
    unico_check_process_id AS id_unico_check_process,
    version,
    typed,
    type,
    ocr,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.unico_check_document
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}