-- Product & Tech team formation roster for the Full Base 5A sheet (L1-scoped active employees).
WITH cost_center_label AS (
    SELECT
        es.assignment_number,
        CONCAT(
            LOWER(es.cost_center_code),
            ' - ',
            SUBSTRING(LOWER(es.cost_center_name), 10)
        ) AS cost_center_label
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
        AND es.is_primary_assignment_for_snapshot = TRUE
)
SELECT DISTINCT
    COALESCE(LOWER(es.name), '') AS `Employees name`,
    COALESCE(LOWER(es.work_email), '') AS Email,
    COALESCE(CAST(es.dt_original_hire AS STRING), '') AS Admission,
    COALESCE(LOWER(es.manager_name), '') AS Manager,
    COALESCE(LOWER(es.assignment_number), '') AS assignment_number,
    COALESCE(LOWER(CAST(es.band AS STRING)), '') AS Department,
    COALESCE(cc.cost_center_label, '') AS `Cost Center`,
    '' AS `Sub-Directorate`,
    COALESCE(
        CASE
            WHEN es.is_manager IS TRUE THEN 'L'
            ELSE 'CI'
        END,
        ''
    ) AS fl_lider,
    COALESCE(CAST(es.count_direct_report AS STRING), '') AS `Direct Headcount`,
    COALESCE(CAST(tf.team_1 AS STRING), '') AS `Team_1__Primary`,
    COALESCE(CAST(tf.team_2 AS STRING), '') AS Team_2,
    COALESCE(CAST(tf.team_3 AS STRING), '') AS Team_3,
    COALESCE(CAST(tf.team_4 AS STRING), '') AS Team_4,
    COALESCE(CAST(tf.team_5 AS STRING), '') AS Team_5,
    COALESCE(CAST(tf.team_6 AS STRING), '') AS Team_6,
    COALESCE(CAST(tf.team_7 AS STRING), '') AS Team_7,
    COALESCE(CAST(tf.team_8 AS STRING), '') AS Team_8,
    COALESCE(CAST(tf.team_9 AS STRING), '') AS Team_9,
    COALESCE(CAST(tf.team_10 AS STRING), '') AS Team_10,
    COALESCE(tf.line_leader, '') AS Line_Leader,
    COALESCE(tf.team_leader, '') AS Team_Leader,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
LEFT JOIN
    cost_center_label AS cc
        ON cc.assignment_number = es.assignment_number
LEFT JOIN
    datalake_gsheets_people_clean.team_formation_product_tech AS tf
        ON es.person_number = regexp_extract(LOWER(tf.assignment_number), '[ec](\\d+)', 1)
WHERE
    es.is_current_for_employee = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
    AND LOWER(es.status) = 'active'
    AND LOWER(NULLIF(es.owner_l1_name, '-1')) IN (
        'paulo braz golgher',
        'larissa fontaine',
        'rafael dantas de castro'
    )
    AND cc.cost_center_label NOT IN (
        '475x1x - credit analytics',
        '202r2x - collections backoffice',
        '138x1x - service - collections & evictions',
        '201r2x - collections',
        '130q2x - service team',
        '201q2x - collections',
        '440q2x - credit',
        '722s2x - collections',
        '201r1x - collections'
    )
ORDER BY
    `Employees name` ASC
