SELECT
    id,
    unico_check_process_id AS id_unico_check_process,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    typed,
    type,
    ocr,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.unico_check_document_aud
