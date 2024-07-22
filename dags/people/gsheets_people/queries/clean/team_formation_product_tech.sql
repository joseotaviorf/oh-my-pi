SELECT
    MD5(
        CONCAT(
            email,
            subdirectorate,
            team_1_primary,
            COALESCE(team_2, '-1'),
            COALESCE(team_3, '-1'),
            COALESCE(team_4, '-1'),
            COALESCE(team_5, '-1')
        )
    ) AS id,
    employees_name,
    email,
    subdirectorate,
    team_1_primary AS team_1,
    team_2,
    team_3,
    team_4,
    team_5,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.team_formation_product_tech
WHERE
    employees_name <> ''