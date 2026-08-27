-- Active Tech employees with team-formation primary squad for P&T interviewer sheets.
SELECT
    LOWER(TRIM(es.work_email)) AS `email funcionário`,
    es.band AS banda,
    NULLIF(LOWER(es.line), '-1') AS line,
    ptt.team_1 AS neotribe,
    LOWER(TRIM(es.manager_name)) AS lider,
    LOWER(es.country) AS `país`,
    es.months_employee_tenure AS `tempo de casa`,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    dw_people.dim_product_tech_team AS ptt
        ON es.person_number = ptt.person_number
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND LOWER(es.status) = 'active'
    AND LOWER(NULLIF(es.vertical, '-1')) = 'tech'
