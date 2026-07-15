WITH
filtered_assignments_ranked AS (
  SELECT
    assignment_number,
    id_assignment,
    id_person,
    action_code,
    reason_code,
    dt_effective_started,
    dt_effective_ended,
    ROW_NUMBER() OVER (PARTITION BY id_assignment ORDER BY dt_effective_started DESC) AS rn
  FROM
    datalake_pin_core_clean.all_assignments
  WHERE
    assignment_type IN ('E', 'C')
    AND dt_effective_started <= DATE('{load_start_date}')
),
filtered_assignments AS (
  SELECT
    assignment_number,
    id_assignment,
    id_person,
    action_code,
    reason_code,
    dt_effective_started,
    dt_effective_ended
  FROM
    filtered_assignments_ranked
  WHERE
    rn = 1
)
SELECT
  a.id_assignment,
  s.id_manager_assignment,
  a.id_person,
  s.id_manager,
  ei.id_period_of_service,
  eim.id_period_of_service AS id_manager_period_of_service,
  ei.assignment_number,
  eim.assignment_number AS manager_assignment_number,
  ei.name AS employee_name,
  eim.name AS manager_name,
  s.created_by,
  s.updated_by,
  a.action_code,
  a.reason_code,
  s.dt_effective_started,
  s.dt_effective_ended,
  s.ts_created,
  s.ts_updated,
  NOW() AS ts_load
FROM
  filtered_assignments AS a
LEFT JOIN
  datalake_pin_core_clean.assignment_supervisor AS s
    ON a.id_assignment = s.id_assignment
LEFT JOIN
  datalake_people.identifier_mapping AS ei
    ON ei.id_assignment = s.id_assignment
LEFT JOIN
  datalake_people.identifier_mapping AS eim
    ON eim.id_assignment = s.id_manager_assignment
WHERE
  s.manager_type = 'LINE_MANAGER'
