SELECT
    id,
    report_version_id AS id_report_version,
    document_external_id AS id_external_document,
    description,
    value,
    installments,
    finished AS is_finished,
    created_at AS ts_created,
    year,
    month,
    day
FROM 
    datalake_property_tax_raw.report_item
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}