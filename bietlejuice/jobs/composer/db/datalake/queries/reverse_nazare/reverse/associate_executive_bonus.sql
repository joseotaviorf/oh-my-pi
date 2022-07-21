SELECT
    id_associate_executive AS agent_id,
    id_hub AS business_unit_id,
    dt_bonus AS bonus_start_date,
    dt_bonus_end AS bonus_end_date,
    bonus_value AS bonus_fee,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    datalake_gsheets_clean.associate_executive_bonus
