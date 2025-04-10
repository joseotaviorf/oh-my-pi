SELECT
    id,
    reference_id AS id_reference,
    person_uuid,
    user_person_uuid,
    reference_type,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_docx_raw.person
