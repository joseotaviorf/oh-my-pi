WITH assignment_change_events AS (
  SELECT
    md.id_person AS sk_employee,
    md.id_period_of_service AS sk_assignment,
    COALESCE(CAST(DATE_FORMAT(md.dt_effective_started, "yyyyMMdd") AS BIGINT), -1) AS sk_started_date,
    COALESCE(CAST(DATE_FORMAT(md.dt_effective_ended, "yyyyMMdd") AS BIGINT), -1) AS sk_ended_date,
    'ASSIGNMENT_CHANGE' AS event_type,
    UPPER(md.assignment_name) AS event_value,
    UPPER(md.action_code) AS action_reason,
    CAST(NULL AS STRING) AS currency_code,
    LEAD(UPPER(md.assignment_name)) OVER (
      PARTITION BY md.id_period_of_service
      ORDER BY md.dt_effective_started
    ) AS next_assignment_name
  FROM
    datalake_pin.movement_details AS md
)
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
  datalake_people.identifier_mapping AS ei
    ON s.id_assignment = ei.id_assignment

UNION ALL

SELECT
  sk_employee,
  sk_assignment,
  sk_started_date,
  sk_ended_date,
  event_type,
  event_value,
  action_reason,
  currency_code
FROM
  assignment_change_events
WHERE
  next_assignment_name <> event_value
