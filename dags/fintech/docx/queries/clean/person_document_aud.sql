SELECT
    id,
    rev,
    person_id AS id_person,
    revtype AS rev_type,
    revend AS rev_end,
    type,
    country_code,
    country_code_mod AS mod_country_code,
    type_mod AS mod_type,
    info_list_mod AS mod_info_list,
    person_mod AS mod_person
FROM
    datalake_docx_raw.person_document_aud
