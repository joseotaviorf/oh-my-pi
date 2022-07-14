SELECT
    NULLIF(id_associate_executive, '') AS id_associate_executive,
    NULLIF(id_hub,'') AS id_hub,
    NULLIF(hub,'') AS hub,
    NULLIF(associate_executive,'') AS associate_executive,
    CAST(bonus_value AS FLOAT) AS bonus_value,
    CAST(dt_bonus AS DATE) AS dt_bonus,
    CAST(dt_bonus_end AS DATE) AS dt_bonus_end
FROM
    datalake_gsheets_raw.associate_executive_bonus
WHERE
    COALESCE(NULLIF(id_associate_executive, ''), NULLIF(id_hub,''), NULLIF(hub,''), NULLIF(associate_executive,''), CAST(bonus_value AS FLOAT), CAST(dt_bonus AS DATE), CAST(dt_bonus_end AS DATE)) IS NOT NULL