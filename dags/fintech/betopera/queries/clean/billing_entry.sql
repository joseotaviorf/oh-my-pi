SELECT
    id,
    payment_id AS id_payment,
    prize_amount,
    fee_amount,
    reason,
    status,
    billing_year_month,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.billing_entry
