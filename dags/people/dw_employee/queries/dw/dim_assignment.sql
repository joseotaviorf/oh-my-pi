WITH
salaries AS (
  SELECT
    id_assignment,
    currency_code,
    action_reason
  FROM
    datalake_hr_system_clean.salaries
  WHERE
    dt_from <= DATE('{load_start_date}')
    AND assignment_number NOT LIKE 'P%'
  QUALIFY
    DENSE_RANK() OVER (PARTITION BY id_assignment ORDER BY dt_from DESC, ts_last_update DESC) = 1
)

SELECT
  wr.id_period_of_service AS sk_assignment,
  ei.assignment_number,
  ei.legacy_registration,
  wr.legislation_code,
  wr.worker_type,
  a.assignment_status_type_code,
  a.assignment_status_type,
  COALESCE(a.union_name, '-1') AS union_name,
  IF(wr.dt_termination IS NOT NULL, al.description, -1) AS dismissal_type,
  s.action_reason AS reason_last_salary_increase
FROM
  datalake_hr_system.work_relationships AS wr
LEFT JOIN
  datalake_hr_system.assignment_effective_status AS a
    ON wr.id_period_of_service = a.id_period_of_service
LEFT JOIN
  salaries AS s
    ON a.id_assignment = s.id_assignment
LEFT JOIN
  datalake_hr_system.employee_ids AS ei
    ON ei.id_period_of_service = wr.id_period_of_service
LEFT JOIN
  datalake_hr_system_clean.actions_lov AS al
    ON al.action_code = a.action_code
WHERE
  (
    wr.dt_start <= DATE('{load_start_date}')
    AND wr.worker_type IN ('E', 'C')
  )
  OR (
    a.dt_projected_start > DATE('{load_start_date}')
    AND wr.worker_type = 'P'
  )
