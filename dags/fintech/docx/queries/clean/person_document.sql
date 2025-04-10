SELECT
    id,
    person_id AS id_person,
    type,
    country_code,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_docx_raw.person_document
