SELECT
    id,
    data,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.visit_lead
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}