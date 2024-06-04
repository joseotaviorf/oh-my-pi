SELECT
    employees_name,
    email,
    subdirectorate as sub_directorate,
    team_1_primary as team_1,
    team_2,
    team_3,
    team_4,
    team_5
FROM
    datalake_gsheets_raw.team_formation_product_tech
WHERE
    employees_name <> ''
