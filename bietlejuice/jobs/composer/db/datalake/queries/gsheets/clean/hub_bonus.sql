SELECT
    hub,
    CAST(bonus_fee AS FLOAT) AS bonus_fee,
    CAST(dt_opening AS DATE) AS dt_opening,
    CAST(dt_bonus_cutoff AS DATE) AS dt_bonus_cutoff
FROM
    datalake_gsheets_raw.hub_bonus
