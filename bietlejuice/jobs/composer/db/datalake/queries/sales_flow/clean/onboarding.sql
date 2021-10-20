SELECT
    id AS id_onboarding,
    sales_flow_id AS id_sales_flow,
    deposit_buyer,
    documentation_buyer,
    documentation_seller,
    documentation_house,
    deposit_sent,
    status,
    end_date AS dt_ended,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.onboarding
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}