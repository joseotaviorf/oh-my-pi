SELECT
    dec.sk_employee,
    CASE
        WHEN team_formation_product_tech.team_1 = '' THEN NULL
        ELSE team_formation_product_tech.team_1
    END AS team_1,
    CASE
        WHEN team_formation_product_tech.team_2 = '' THEN NULL
        ELSE team_formation_product_tech.team_2
    END AS team_2,
    CASE
        WHEN team_formation_product_tech.team_3 = '' THEN NULL
        ELSE team_formation_product_tech.team_3
    END AS team_3,
    CASE
        WHEN team_formation_product_tech.team_4 = '' THEN NULL
        ELSE team_formation_product_tech.team_4
    END AS team_4,
    CASE
        WHEN team_formation_product_tech.team_5 = '' THEN NULL
        ELSE team_formation_product_tech.team_5
    END AS team_5
FROM
    datalake_gsheets_clean.team_formation_product_tech
LEFT JOIN dw_employee.dim_employee_contact dec
    ON dec.work_email = team_formation_product_tech.email
