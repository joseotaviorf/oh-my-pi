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
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.document
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}