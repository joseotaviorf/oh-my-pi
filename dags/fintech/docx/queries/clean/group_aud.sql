SELECT
    CAST(id AS BIGINT) AS id_group,
    user_person_uuid AS uuid_user_person,
    user_person_uuid_mod AS mod_uuid_user_person,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    type,
    type_mod AS mod_type,
    sub_type,
    sub_type_mod AS mod_sub_type,
    authorizations_mod AS mod_authorizations,
    members_mod AS mod_members,
    active AS is_active,
    active_mod AS mod_is_active
FROM
    datalake_docx_raw.group_aud
