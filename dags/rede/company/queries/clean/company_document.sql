WITH deleted_rows AS (
    SELECT
        id_document AS id_document_deleted_row,
        id_company AS id_document_company_row
    FROM
        datalake_company_clean.company_document_aud
    WHERE
        rev_type = 2
)
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
    datalake_company_raw.company_document AS c
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_document_deleted_row = c.document_id
        AND dr.id_document_company_row = c.company_id
WHERE
    dr.id_document_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_document, id_company ORDER BY ts_updated DESC) = 1
