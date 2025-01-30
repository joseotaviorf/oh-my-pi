SELECT
    id,
    sales_flow_id AS id_sales_flow,
    tag_id AS id_tag,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_sales_flow_test_raw.sales_flow_tag