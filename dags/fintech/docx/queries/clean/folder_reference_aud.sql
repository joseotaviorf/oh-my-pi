SELECT
    id,
    rev,
    folder_reference_type_id  AS id_folder_reference_type,
    source_folder_id AS id_source_folder,
    target_folder_id AS id_target_folder,
    revtype AS rev_type,
    revend AS rev_end,
    documentation_send_date_mod AS mod_ts_documentation_sent,
    documentation_send_date AS ts_documentation_sent
FROM datalake_docx_raw.folder_reference_aud
