SELECT
    CAST(id AS BIGINT) AS id_group,
    user_person_uuid,
    type,
    sub_type,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_docx_raw.group
