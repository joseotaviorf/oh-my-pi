SELECT
    ei.id_period_of_service AS sk_assignment,
    line,
    chapter,
    team_1,
    team_2,
    team_3,
    team_4,
    team_5,
    team_6,
    team_7,
    team_8,
    team_9,
    team_10,
    line_leader,
    team_leader,
    NOW() AS ts_load
FROM
    datalake_gsheets_clean.team_formation_product_tech AS tfpt
INNER JOIN
    datalake_hr_system.employee_ids AS ei
        ON tfpt.assignment_number = ei.assignment_number
