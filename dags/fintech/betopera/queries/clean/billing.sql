SELECT
    id,
    fee_amount,
    prize_amount,
    status,
    billing_year_month,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.billing
