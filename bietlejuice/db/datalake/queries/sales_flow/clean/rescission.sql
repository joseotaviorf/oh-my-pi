SELECT
    id AS id_rescission,
    sales_flow_id AS id_sales_flow,
    reason,
    comment,
    rescission_date AS dt_rescission,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.rescission
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}