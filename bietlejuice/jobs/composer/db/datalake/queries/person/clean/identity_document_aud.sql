SELECT
    id,
    person_id AS id_person,
    identification_number,
    document_validation_status,
    document_type,
    issuing_country,
    extra_info,
    attachment_path,
    document_name,
    status,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    person_id_mod AS mod_id_person,
    identification_number_mod AS mod_identification_number,
    document_type_mod AS mod_document_type,
    issuing_country_mod AS mod_issuing_country,
    extra_info_mod AS mod_extra_info,
    attachment_path_mod AS mod_attachment_path,
    document_validation_status_mod AS mod_document_validation_status,
    document_name_mod AS mod_document_name,
    status_mod AS mod_status,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_person_raw.identity_document_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
