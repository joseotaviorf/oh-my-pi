SELECT
    id,
    sales_flow_id AS id_sales_flow,
    house_id AS id_house,
    signed_document_token, 
    unsigned_document_token,
    sale_value AS sale_price,
    ccv_version,
    status,
    signed_at AS ts_signed,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv
