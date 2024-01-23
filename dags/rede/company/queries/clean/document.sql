WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_company_clean.document_aud
    WHERE
        rev_type = 2
)
SELECT
    id,
    company_uuid AS uuid_company,
    identification_number,
    document_validation_status,
    document_type,
    attachment_path,
    extra_info,
    document_name,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.document AS d 
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = d.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
