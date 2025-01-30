SELECT
    id,
    sales_flow_id AS id_sales_flow,
    user_id AS id_user,
    type,
    is_original_user,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_sales_flow_test_raw.sales_flow_users