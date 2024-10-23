SELECT
    id,
    documentation_report_id AS id_documentation_report,
    name,
    url,
    type,
    content_type,
    sequence,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_arquivo_confidencial_raw.documents
