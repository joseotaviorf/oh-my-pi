SELECT
    id,
    CAST(group_id AS BIGINT) AS id_group,
    reference_id AS id_reference,
    reference_type,
    role,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_docx_raw.group_member
