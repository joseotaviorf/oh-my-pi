SELECT
    MD5(
        CONCAT(
            assignment_number,
            line,
            chapter,
            team_1_primary,
            COALESCE(team_2, '-1'),
            COALESCE(team_3, '-1'),
            COALESCE(team_4, '-1'),
            COALESCE(team_5, '-1'),
            COALESCE(team_6, '-1'),
            COALESCE(team_7, '-1'),
            COALESCE(team_8, '-1'),
            COALESCE(team_9, '-1'),
            COALESCE(team_10, '-1'),
            COALESCE(line_leader, '-1'),
            COALESCE(team_leader, '-1')
        )
    ) AS id,
    UPPER(assignment_number) AS assignment_number,
    employees_name AS employee_name,
    email,
    manager,
    department,
    cost_center,
    subdirectorate,
    NULLIF(line, '') AS line,
    NULLIF(chapter, '') AS chapter,
    NULLIF(team_1_primary, '') AS team_1,
    NULLIF(team_2, '') AS team_2,
    NULLIF(team_3, '') AS team_3,
    NULLIF(team_4, '') AS team_4,
    NULLIF(team_5, '') AS team_5,
    NULLIF(team_6, '') AS team_6,
    NULLIF(team_7, '') AS team_7,
    NULLIF(team_8, '') AS team_8,
    NULLIF(team_9, '') AS team_9,  
    NULLIF(team_10, '') AS team_10,
    NULLIF(line_leader, '') AS line_leader,
    NULLIF(team_leader, '') AS team_leader,
    NULLIF(fl_lider, '') AS career_track,
    BOOLEAN(is_line_leader) AS is_line_leader,
    BOOLEAN(is_team_leader) AS is_team_leader,
    INT(direct_headcount) AS direct_headcount,
    TO_DATE(admission, 'dd/MM/yyyy') AS dt_admissioned,
    NOW() AS ts_load
FROM
    datalake_gsheets_people_raw.team_formation_product_tech
WHERE
    employees_name <> ''