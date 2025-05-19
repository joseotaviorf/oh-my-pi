WITH 
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
    datalake_pin_core_clean.all_assignments
  WHERE 
    is_primary
    AND assignment_type IN ('E', 'C', 'P', 'N')
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY id_person ORDER BY dt_effective_ended DESC) = 1
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
  pn.display_name AS employee_name,
  pnm.display_name AS manager_name,
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
  datalake_pin_core_clean.person_name AS pn
    ON pn.id_person = s.id_person
LEFT JOIN 
  datalake_pin_core_clean.person_name AS pnm
    ON pnm.id_person = s.id_manager
LEFT JOIN 
  datalake_hr_system.employee_ids AS ei
    ON ei.id_assignment = s.id_assignment
LEFT JOIN 
  datalake_hr_system.employee_ids AS eim
    ON eim.id_person = s.id_manager
WHERE 
  s.is_primary
  AND s.manager_type = 'LINE_MANAGER'
  AND pn.name_type = 'GLOBAL' 
  AND pn.dt_effective_ended = '4712-12-31'
  AND pnm.name_type = 'GLOBAL' 
  AND pnm.dt_effective_ended = '4712-12-31'
