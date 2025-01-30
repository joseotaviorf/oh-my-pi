SELECT
    id,
    sales_flow_id AS id_sales_flow,
    status_id AS id_status,
    status_start_date AS ts_status_start,
    status_end_date AS ts_status_end,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.status_record