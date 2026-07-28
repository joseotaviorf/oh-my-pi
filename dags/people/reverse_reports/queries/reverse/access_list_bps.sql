-- Base access-control list (assignment_number, email, HRBP/leadership access_list) for other reverse reports to consume.
WITH
access_list_rows AS (
    SELECT
        es.assignment_number AS assignment_number,
        LOWER(es.work_email) AS email,
        es.access_list_no_employee AS access_list,
        ROW_NUMBER() OVER (
            PARTITION BY
                LOWER(es.work_email)
            ORDER BY
                CASE
                    WHEN LOWER(es.status) = 'active' THEN 0
                    ELSE 1
                END,
                es.person_number DESC
        ) AS rn
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
        AND es.work_email IS NOT NULL
)
SELECT
    assignment_number,
    email,
    access_list,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    access_list_rows
WHERE
    rn = 1
