SELECT
    id,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    billing_year_month,
    fee_amount,
    prize_amount,
    status,
    created_at_mod AS mod_created_at,
    updated_at_mod AS mod_updated_at,
    billing_year_month_mod AS mod_billing_year_month,
    fee_amount_mod AS mod_fee_amount,
    prize_amount_mod AS mod_prize_amount,
    status_mod AS mod_status,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.billing_aud
