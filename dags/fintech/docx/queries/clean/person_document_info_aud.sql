SELECT
    id,
    person_document_id AS id_person_document,
    input_source_id AS id_input_source,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    input_source_type,
    input_value_type,
    validation_type,
    type,
    status,
    input_value,
    input_type,
    validated_by,
    input_mod AS mod_input,
    status_mod AS mod_status,
    type_mod AS mod_type,
    person_document_mod AS mod_person_document,
    last_validated_at AS ts_last_validated
FROM
    datalake_docx_raw.person_document_info_aud
