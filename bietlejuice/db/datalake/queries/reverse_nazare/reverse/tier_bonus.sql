SELECT
    kind AS agent_role,
    sk_user AS agent_id,
    dt_tier_start AS bonus_start_date,
    dt_tier_end AS bonus_end_date,
    comission_percentage AS baseline_fee,
    additional_comission_percentage AS bonus_fee,
    tier AS tier_description,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    datalake_gsheets_clean.sale_payments_tiers
