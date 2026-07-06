SELECT
    id,
    sales_flow_id as id_sales_flow,
    pendency,
    type,
    created_at as ts_created,
    updated_at as ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.sales_flow_pendency

