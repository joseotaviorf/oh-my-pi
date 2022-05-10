SELECT
    id,
    buyer_id AS id_buyer,
    seller_id AS id_seller,
    house_id AS id_house,
    monday_id AS id_monday,
    flow_step,
    flow_type,
    status_closing,
    status,
    closing_canceled_reason,
    is_canceled,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.sales_flow
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
