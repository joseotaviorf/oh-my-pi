SELECT
    id,
    sales_flow_id AS id_sales_flow,
    signed_document_reference AS uuid_signed_document_reference,
    unsigned_document_reference AS uuid_unsigned_document_reference,
    signed_document_origin,
    status,
    template_version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.tic
