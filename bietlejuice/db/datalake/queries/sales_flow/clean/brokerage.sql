SELECT
    id AS id_brokerage,
    sales_flow_id AS id_sales_flow,
    quinto_andar_brokerage_split,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.brokerage
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}