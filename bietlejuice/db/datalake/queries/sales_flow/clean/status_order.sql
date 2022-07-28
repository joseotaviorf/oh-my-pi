SELECT
    id,
    closing_type_id AS id_closing_type,
    status_id AS id_status,
    ordering,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.status_order
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
