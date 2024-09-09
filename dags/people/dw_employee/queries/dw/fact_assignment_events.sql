SELECT
  ei.id_person AS sk_employee,
  ei.id_period_of_service AS sk_assignment,
  COALESCE(CAST(DATE_FORMAT(s.dt_from, "yyyyMMdd") AS BIGINT), -1) AS sk_started_date,
  COALESCE(CAST(DATE_FORMAT(s.dt_to, "yyyyMMdd") AS BIGINT), -1) AS sk_ended_date,
  'SALARY_ADJUSTMENT' AS event_type,
  s.salary_amount AS event_value,
  UPPER(s.action_reason) AS action_reason,
  s.currency_code
FROM
  datalake_hr_system_clean.salaries AS s
LEFT JOIN
  datalake_hr_system.employee_ids AS ei
    ON s.id_assignment = ei.id_assignment
