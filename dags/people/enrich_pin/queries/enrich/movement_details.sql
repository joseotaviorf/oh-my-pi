SELECT DISTINCT
  aa.id_person,
  aa.id_period_of_service,
  aa.id_assignment,
  aa.id_business_unit,
  aa.id_organization AS id_cost_center,
  aa.id_job,
  aa.id_grade_ladder_program AS id_band_ladder,
  aa.assignment_number,
  aa.assignment_type,
  UPPER(aa.assignment_name) AS assignment_name,
  aa.assignment_status_type,
  aa.action_code,
  g.grade_code AS band,
  pglt.name AS comp_ladder_directorate,
  obu.name AS business_unit_name,
  occ.name AS cost_center_name,
  aa.dt_effective_started,
  aa.dt_effective_ended,
  NOW() AS ts_load
FROM
  datalake_pin_core_clean.all_assignments AS aa
LEFT JOIN
  datalake_pin_core_clean.grade AS g
    ON g.id_grade = aa.id_grade
    AND g.dt_effective_ended = DATE('9999-12-31')
LEFT JOIN
  datalake_hr_system_clean.organizations AS occ
    ON occ.id_organization = aa.id_organization
LEFT JOIN
  datalake_hr_system_clean.organizations AS obu
    ON obu.id_organization = aa.id_business_unit
LEFT JOIN
  datalake_pin_core_clean.grade_ladder AS pgl
    ON pgl.id_grade_ladder = aa.id_grade_ladder_program
    AND aa.dt_effective_started BETWEEN pgl.dt_effective_started AND pgl.dt_effective_ended
LEFT JOIN
  datalake_pin_core_clean.grade_ladder_translation AS pglt
    ON pglt.id_grade_ladder = pgl.id_grade_ladder
    AND pglt.language = 'PTB'
    AND aa.dt_effective_started BETWEEN pglt.dt_effective_started AND pglt.dt_effective_ended
WHERE
  aa.assignment_type IN ('E', 'C', 'P')