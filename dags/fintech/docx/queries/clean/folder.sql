SELECT
    id,
    external_id AS id_external,
    folder_type_id AS id_folder_type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM datalake_docx_raw.folder
