WITH
    talent_access_list_rows AS (
        SELECT
            es.person_number AS person_number,
            es.access_list_no_employee_no_hrbp AS access_list,
            ROW_NUMBER() OVER (
                PARTITION BY
                    es.person_number
                ORDER BY
                    CASE
                        WHEN LOWER(es.status) = 'active' THEN 0
                        ELSE 1
                    END,
                    es.assignment_number DESC
            ) AS rn
        FROM
            metric_people.employee_snapshots AS es
        WHERE
            es.is_current_for_employee = TRUE
    )
SELECT
    person_number,
    access_list,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    talent_access_list_rows
WHERE
    rn = 1
