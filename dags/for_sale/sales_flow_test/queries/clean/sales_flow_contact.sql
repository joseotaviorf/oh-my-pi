SELECT
    id AS id_sales_flow_contact,
    sales_flow_id AS id_sales_flow,
    contact_id AS id_contact,
    type,
    default_type AS is_default_type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_sales_flow_test_raw.sales_flow_contact