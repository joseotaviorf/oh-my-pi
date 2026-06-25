WITH
    employee_base AS (
        SELECT
            es.*
        FROM
            metric_people.employee_snapshots AS es
        WHERE
            es.is_current = TRUE
            AND es.is_primary_assignment_for_snapshot = TRUE
    ),
    manager_profile AS (
        SELECT DISTINCT
            eb.assignment_number,
            eb.job_name AS cargo,
            eb.band
        FROM
            employee_base AS eb
    )
SELECT
    bc.name AS nome,
    LOWER(bc.work_email) AS email,
    bc.job_name AS cargo,
    bc.band AS banda,
    bc.job_family AS classe_cargo,
    mh.name_l0 AS l0,
    LOWER(mh.email_l0) AS l0_email,
    c0.cargo AS cargo_l0,
    c0.band AS banda_l0,
    mh.name_l1 AS l1,
    LOWER(mh.email_l1) AS l1_email,
    c1.cargo AS cargo_l1,
    c1.band AS banda_l1,
    mh.name_l2 AS l2,
    LOWER(mh.email_l2) AS l2_email,
    c2.cargo AS cargo_l2,
    c2.band AS banda_l2,
    mh.name_l3 AS l3,
    LOWER(mh.email_l3) AS l3_email,
    c3.cargo AS cargo_l3,
    c3.band AS banda_l3,
    mh.name_l4 AS l4,
    LOWER(mh.email_l4) AS l4_email,
    c4.cargo AS cargo_l4,
    c4.band AS banda_l4,
    mh.name_l5 AS l5,
    LOWER(mh.email_l5) AS l5_email,
    c5.cargo AS cargo_l5,
    c5.band AS banda_l5,
    mh.name_l6 AS l6,
    LOWER(mh.email_l6) AS l6_email,
    c6.cargo AS cargo_l6,
    c6.band AS banda_l6,
    mh.name_l7 AS l7,
    LOWER(mh.email_l7) AS l7_email,
    c7.cargo AS cargo_l7,
    c7.band AS banda_l7,
    mh.name_l8 AS l8,
    LOWER(mh.email_l8) AS l8_email,
    c8.cargo AS cargo_l8,
    c8.band AS banda_l8,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    employee_base AS bc
LEFT JOIN
    dw_employee_details.dim_management_hierarchy AS mh
        ON mh.assignment_number = bc.assignment_number
        AND mh.is_current = TRUE
LEFT JOIN
    manager_profile AS c0
        ON c0.assignment_number = mh.assignment_number_l0
LEFT JOIN
    manager_profile AS c1
        ON c1.assignment_number = mh.assignment_number_l1
LEFT JOIN
    manager_profile AS c2
        ON c2.assignment_number = mh.assignment_number_l2
LEFT JOIN
    manager_profile AS c3
        ON c3.assignment_number = mh.assignment_number_l3
LEFT JOIN
    manager_profile AS c4
        ON c4.assignment_number = mh.assignment_number_l4
LEFT JOIN
    manager_profile AS c5
        ON c5.assignment_number = mh.assignment_number_l5
LEFT JOIN
    manager_profile AS c6
        ON c6.assignment_number = mh.assignment_number_l6
LEFT JOIN
    manager_profile AS c7
        ON c7.assignment_number = mh.assignment_number_l7
LEFT JOIN
    manager_profile AS c8
        ON c8.assignment_number = mh.assignment_number_l8
WHERE
    bc.is_active = TRUE
    OR bc.dt_terminated > CURRENT_DATE()
