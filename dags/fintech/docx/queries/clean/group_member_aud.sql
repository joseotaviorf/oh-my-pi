SELECT
    id,
    CAST(group_id AS BIGINT) AS id_group,
    reference_id AS id_reference,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    reference_type,
    reference_mod AS mod_reference,
    role,
    role_mod AS mod_role
FROM
    datalake_docx_raw.group_member_aud
