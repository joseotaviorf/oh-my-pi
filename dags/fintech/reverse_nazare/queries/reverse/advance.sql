SELECT
    id_offer AS offer_id,
    id_agent AS agent_id,
    gross_advance AS bonus_fee,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    datalake_gsheets_clean.advance_base
