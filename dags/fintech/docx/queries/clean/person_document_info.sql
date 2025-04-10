SELECT
    id,
    person_document_id AS id_person_document,
    input_source_id AS id_input_source,
    input_source_type,
    input_value_type,
    validation_type,
    type,
    version,
    status,
    input_value,
    input_type,
    validated_by,
    last_validated_at AS ts_last_validated,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_docx_raw.person_document_info
