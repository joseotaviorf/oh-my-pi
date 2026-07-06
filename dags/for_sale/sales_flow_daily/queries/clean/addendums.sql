SELECT
    id,
    sales_flow_id AS id_sales_flow,
    ccv_id AS id_ccv,
    status,
    signed_at AS ts_signed,
    signed_document_token,
    unsigned_document_token,
    reasons,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.addendums
