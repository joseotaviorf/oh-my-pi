WITH deleted_rows AS (
    SELECT
        id AS id_deleted_row
    FROM
        datalake_person_clean.identity_document_aud
    WHERE
        rev_type = 2
)
SELECT
    id,
    documentuuid AS uuid_document,
    person_id AS id_person,
    identification_number,
    document_validation_status,
    document_type,
    issuing_country,
    extra_info,
    attachment_path,
    document_name,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.identity_document AS i
LEFT JOIN
    deleted_rows AS dr
        ON dr.id_deleted_row = i.id
WHERE
    dr.id_deleted_row IS NULL
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
