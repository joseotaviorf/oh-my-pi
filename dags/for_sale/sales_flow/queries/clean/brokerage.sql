SELECT
    id AS id_brokerage,
    sales_flow_id AS id_sales_flow,
    brokerage_fee_payer,
    brokerage_payment_timeframe,
    brokerage_fee,
    quinto_andar_brokerage_split,
    brokerage_payment_deadline,
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