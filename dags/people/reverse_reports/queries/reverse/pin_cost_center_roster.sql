SELECT
    es.person_number,
    LOWER(es.cost_center_code) AS cost_center_code,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    metric_people.employee_snapshots AS es
WHERE
    es.is_current = TRUE
    AND es.is_primary_assignment_for_snapshot = TRUE
