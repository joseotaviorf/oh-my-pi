SELECT
    id,
    person_id AS id_person,
    documentuuid AS uuid_document,
    document_type,
    income_nature,
    extra_info,
    attachment_path,
    document_name,
    validation_status,
    status,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    person_id_mod AS mod_id_person,
    documentuuid_mod AS mod_uuid_document,
    document_type_mod AS mod_document_type,
    income_nature_mod AS mod_income_nature,
    extra_info_mod AS mod_extra_info,
    attachment_path_mod AS mod_attachment_path,
    document_name_mod AS mod_document_name,
    validation_status_mod AS mod_validation_status,
    status_mod AS mod_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.income_document_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}