SELECT
    id AS id_report_item,
    report_version_id AS id_report_version,
    document_external_id AS id_external_document,
    description,
    finished AS is_finished,
    value,
    installments,
    created_at AS ts_created
FROM
    datalake_property_tax_raw.report_item
