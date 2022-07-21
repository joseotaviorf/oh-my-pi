SELECT
    offer_flow AS negotiation_type,
    partner_type AS agent_role,
    dt_started AS bonus_start_date,
    dt_ended AS bonus_end_date,
    brokerage_fee_partner AS bonus_fee,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    datalake_gsheets_clean.business_rules_bonus
