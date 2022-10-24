SELECT
    id_offer AS offer_id,
    id_agent AS agent_id,
    hub AS business_unit_id,
    partner_type AS agent_role,
    campaign AS description,
    dt_started AS start_date,
    dt_ended AS end_date,
    campaign_bonus AS bonus_fee,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    datalake_gsheets_clean.campaign_bonus
