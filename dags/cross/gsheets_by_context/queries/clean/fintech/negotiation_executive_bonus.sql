SELECT
    id_negotiation_executive,
    id_hub,
    hub,
    CAST(bonus_value AS FLOAT) AS bonus_value,
    CAST(dt_bonus AS DATE) AS dt_bonus,
    CAST(dt_bonus_end AS DATE) AS dt_bonus_end
FROM
    datalake_gsheets_raw.negotiation_executive_bonus
