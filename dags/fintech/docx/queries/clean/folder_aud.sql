SELECT
    id,
    external_id AS id_external,
    folder_type_id AS id_folder_type,
    rev,
    revtype AS rev_type,
    revend AS rev_end
FROM datalake_docx_raw.folder_aud
