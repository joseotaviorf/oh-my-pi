WITH 
band_ladder AS (
  SELECT
    a.GradeLadderId AS id_band_ladder,
    a.GradeLadderName AS comp_ladder_directorate,
    ad.EffectiveStartDate AS dt_effective_started
  FROM
    datalake_hr_system_clean.workers AS w
  LATERAL VIEW
    EXPLODE(w.work_relationships) AS wr
  LATERAL VIEW
    EXPLODE(wr.assignments) AS a
  LATERAL VIEW
    EXPLODE(a.assignmentsDFF) AS ad
  QUALIFY
    ROW_NUMBER() 
      OVER (PARTITION BY id_band_ladder ORDER BY dt_effective_started DESC) = 1
)

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
    bl.comp_ladder_directorate,
    obu.name AS business_unit_name,
    occ.name AS cost_center_name,
    aa.dt_effective_started,
    aa.dt_effective_ended,
    NOW() AS ts_load
FROM
  datalake_pin_core_clean.all_assignments AS aa
LEFT JOIN
  datalake_pin_core_clean.action_occurrence AS ao
    ON ao.id_action_occurrence = aa.id_action_occurrence
LEFT JOIN
  datalake_pin_core_clean.action_reason_base AS arb
    ON arb.id_action_reason = ao.id_action_reason
LEFT JOIN
  datalake_pin_core_clean.grade AS g 
    ON g.id_grade = aa.id_grade
    AND g.dt_effective_ended = DATE('4712-12-31')
LEFT JOIN 
  datalake_hr_system_clean.organizations AS occ 
    ON occ.id_organization = aa.id_organization   
LEFT JOIN 
  datalake_hr_system_clean.organizations AS obu 
    ON obu.id_organization = aa.id_business_unit
LEFT JOIN 
  band_ladder AS bl 
    ON bl.id_band_ladder = aa.id_grade_ladder_program      
WHERE 
  aa.assignment_type IN ('E', 'C', 'P')