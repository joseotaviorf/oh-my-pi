SELECT
    hub,
    associate_executive,
    CAST(bonus_value AS FLOAT) AS bonus_value,
    CAST(dt_bonus AS DATE) AS dt_bonus
FROM
    datalake_gsheets_raw.associate_executive_bonus
