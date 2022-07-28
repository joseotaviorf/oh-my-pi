SELECT
    id AS id_ccv_flow,
    sales_flow_id AS id_sales_flow,
    status,
    started_confection_at AS ts_confection_started,
    signed_at AS ts_signed,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv_flow
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}