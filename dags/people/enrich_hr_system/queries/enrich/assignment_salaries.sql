WITH
    salaries_cte AS (
        SELECT
            s.id_assignment,
            s.currency_code,
            s.salary_amount,
            s.dt_from AS dt_salary_started,
            s.dt_to,
            LEAD (s.dt_from, 1) OVER (
                PARTITION BY
                    id_assignment
                ORDER BY
                    s.dt_from
            ) AS next_dt_salary_started,
            CASE
                WHEN dt_to + 1 <> next_dt_salary_started
                AND next_dt_salary_started IS NOT NULL THEN next_dt_salary_started - 1
                ELSE dt_to
            END AS dt_salary_ended,
            s.action_reason
        FROM
            datalake_hr_system_clean.salaries AS s
    )
SELECT
    a.id_person,
    a.id_assignment,
    a.id_period_of_service,
    a.assignment_name,
    a.band,
    a.cost_center_name,
    s.action_reason,
    s.currency_code,
    s.salary_amount,
    a.dt_effective_start AS dt_assignment_started,
    a.dt_effective_end AS dt_assignment_ended,
    dt_salary_started,
    dt_salary_ended
FROM
    datalake_hr_system.assignments AS a
    FULL OUTER JOIN salaries_cte AS s ON s.id_assignment = a.id_assignment
    AND (
        dt_salary_started BETWEEN dt_effective_start AND dt_effective_end
        OR dt_salary_ended BETWEEN dt_effective_start AND dt_effective_end
        OR dt_effective_start BETWEEN dt_salary_started AND dt_salary_ended
        OR dt_effective_end BETWEEN dt_salary_started AND dt_salary_ended
    )
WHERE
    a.assignment_status_type = 'ACTIVE'
