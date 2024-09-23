SELECT
    id AS id_file,
    closing_id AS id_closing,
    user_id AS id_user,
    storage_documento_id AS id_document,
    file_key,
    file_hash,
    file_name,
    comments,
    TO_TIMESTAMP(created_at) AS ts_created
FROM
    datalake_atta_raw.closing_file
