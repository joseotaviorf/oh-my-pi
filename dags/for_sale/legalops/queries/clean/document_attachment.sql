SELECT
    id,
    attachment_name,
    document_id,
    document_file_type,
    service_owner,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_legalops_raw.document_attachment
