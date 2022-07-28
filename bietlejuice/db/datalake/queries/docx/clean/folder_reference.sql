SELECT
    id,
    folder_reference_type_id AS id_folder_reference_type,
    source_folder_id AS id_source_folder,
    target_folder_id AS id_target_folder,
    reference_properties,
    documentation_send_date AS ts_documentation_sent,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_docx_raw.folder_reference
