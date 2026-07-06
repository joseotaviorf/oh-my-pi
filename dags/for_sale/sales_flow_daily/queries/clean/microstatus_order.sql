SELECT
    id,
    status_order_id AS id_status_order,
    status_id AS id_status,
    ordering,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.microstatus_order

