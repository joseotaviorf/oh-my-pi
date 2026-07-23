WITH
salaries_ranked AS (
  SELECT
    id_assignment,
    action_reason,
    ROW_NUMBER() OVER (
      PARTITION BY id_assignment
      ORDER BY dt_from DESC, ts_last_update DESC
    ) AS rn
  FROM
    datalake_hr_system_clean.salaries
  WHERE
    dt_from <= DATE('{load_start_date}')
),
salaries AS (
  SELECT
    id_assignment,
    action_reason
  FROM
    salaries_ranked
  WHERE
    rn = 1
),
unions_ranked AS (
  SELECT
    wr.PeriodOfServiceId AS id_period_of_service,
    a.UnionName AS union_name,
    ROW_NUMBER() OVER (
      PARTITION BY wr.PeriodOfServiceId
      ORDER BY w.dt_effective DESC
    ) AS rn
  FROM
    datalake_hr_system_clean.workers AS w
  LATERAL VIEW OUTER
    EXPLODE(w.work_relationships) AS wr
  LATERAL VIEW OUTER
    EXPLODE(wr.assignments) AS a
  WHERE
    TO_DATE(w.dt_effective, 'yyyyMMdd') <= DATE('{load_end_date}')
),
unions AS (
  SELECT
    id_period_of_service,
    union_name
  FROM
    unions_ranked
  WHERE
    rn = 1
)
SELECT
  ed.id_period_of_service AS sk_assignment,
  ed.assignment_number,
  ed.legacy_registration,
  ed.legislation_code,
  ed.assignment_type AS worker_type,
  ed.assignment_status_type,
  COALESCE(u.union_name, -1) AS union_name,
  ed.dismissal_type,
  s.action_reason AS reason_last_salary_increase,
  NOW() AS ts_load
FROM
  datalake_employment.employee_details AS ed
LEFT JOIN
  unions AS u
    ON u.id_period_of_service = ed.id_period_of_service
LEFT JOIN
  salaries AS s
    ON s.id_assignment = ed.id_assignment
