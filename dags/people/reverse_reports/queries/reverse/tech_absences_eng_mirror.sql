-- Approved absences for Paulo Golgher L1 roster (Engineering tab).
WITH current_paulo_roster AS (
    SELECT
        LOWER(es.assignment_number) AS assignment_number,
        LOWER(es.name) AS employee_name,
        LOWER(es.work_email) AS email
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current_for_employee = TRUE
        AND es.is_primary_assignment_for_snapshot = TRUE
        AND LOWER(es.status) = 'active'
        AND LOWER(es.email_l1) = 'paulo.golgher@quintoandar.com.br'
)
SELECT DISTINCT
    far.assignment_number,
    ce.employee_name AS nome,
    ce.email,
    CASE
        WHEN dat.absence_type = 'Férias' THEN 'Vacation'
        ELSE 'Other reasons'
    END AS absence_type,
    far.dt_absence_started,
    far.dt_absence_ended,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    dw_time.fact_absence_requests AS far
INNER JOIN
    current_paulo_roster AS ce
        ON LOWER(far.assignment_number) = ce.assignment_number
LEFT JOIN
    dw_time.dim_absence_type AS dat
        ON far.sk_absence_type = dat.sk_absence_type
WHERE
    far.is_approved = TRUE
    AND (
        far.dt_absence_started >= DATE '2025-01-01'
        OR far.dt_absence_ended >= DATE '2025-01-01'
    )
ORDER BY
    nome ASC,
    dt_absence_started ASC
