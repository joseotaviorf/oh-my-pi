SELECT
    document_id AS id_document,
    company_id AS id_company,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.company_document
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_document, id_company ORDER BY ts_updated DESC) = 1
