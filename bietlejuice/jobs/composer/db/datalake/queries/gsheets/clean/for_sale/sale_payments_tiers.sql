SELECT
    BIGINT(sk_user),
    BIGINT(sk_agent),
    CAST(REPLACE(comission, '%', '') AS FLOAT) AS comission_percentage,
    kind,
    tier,
    TO_DATE(tier_start_date, 'dd/MM/yyyy') AS dt_tier_start,
    TO_DATE(tier_end_date, 'dd/MM/yyyy') AS dt_tier_end
FROM
    datalake_gsheets_raw.sale_payments_tiers
