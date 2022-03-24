SELECT
    hub,
    CAST(bonus_value AS FLOAT) AS bonus_value,
    CAST(dt_bonus AS DATE) AS dt_bonus
FROM
    datalake_gsheets_raw.negotiation_executive_bonus
