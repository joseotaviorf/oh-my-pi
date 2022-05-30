SELECT
    id,
    company_uuid AS uuid_company,
    identification_number,
    document_validation_status,
    document_type,
    attachment_path,
    extra_info,
    document_name,
    status,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    company_uuid_mod AS mod_uuid_company,
    identification_number_mod AS mod_identification_number,
    document_type_mod AS mod_document_type,
    attachment_path_mod AS mod_attachment_path,
    extra_info_mod AS mod_extra_info,
    document_validation_status_mod AS mod_document_validation_status,
    document_name_mod AS mod_document_name,
    status_mod AS mod_status,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_company_raw.document_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}