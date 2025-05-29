SELECT
    id,
    rev,
    reference_id AS id_reference,
    person_uuid,
    user_person_uuid,
    reference_type,
    revtype AS rev_type,
    revend AS rev_end,
    reference_mod AS mod_reference,
    user_person_uuid_mod AS mod_user_person_uuid,
    documents_mod AS mod_documents
FROM
    datalake_docx_raw.person_aud
