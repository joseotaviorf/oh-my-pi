SELECT
    id,
    process_id AS id_process,
    external_id AS id_external,
    api_key,
    document_value,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    status,
    result,
    payload,
    expiration_date AS ts_expiration
FROM
    datalake_arquivo_confidencial_raw.truora_check_process_aud
