WITH
terminated_employees AS (
  SELECT DISTINCT
    id_period_of_service,
    assignment_status_type,
    assignment_status_type_code,
    action_code,
    reason_code,
    dt_assignment_started AS dt_effective_start,
    dt_assignment_ended AS dt_effective_end
  FROM
    datalake_hr_system.assignment_snapshot
  WHERE
    assignment_status_type = 'INACTIVE'
    AND assignment_type <> 'P'
    AND (
      is_current_info OR
      is_future_info
    )
  QUALIFY
    DENSE_RANK() OVER (PARTITION BY id_period_of_service ORDER BY dt_effective_start DESC) = 1
)

SELECT
  a.id_assignment,
  a.id_person,
  a.id_period_of_service,
  a.id_business_unit,
  a.id_assignment_status_type,
  a.id_user_person_type,
  a.id_proposed_user_person_type,
  a.id_job,
  a.id_grade AS id_band,
  a.id_grade_ladder AS id_band_ladder,
  a.id_department AS id_cost_center,
  a.id_union,
  a.assignment_number,
  a.assignment_name,
  COALESCE(te.action_code, a.action_code) AS action_code,
  COALESCE(te.reason_code, a.reason_code) AS reason_code,
  a.assignment_sequence AS effective_sequence,
  a.business_unit_name,
  a.assignment_type,
  COALESCE(te.assignment_status_type_code, a.assignment_status_type_code) AS assignment_status_type_code,
  COALESCE(te.assignment_status_type, a.assignment_status_type) AS assignment_status_type,
  a.system_person_type,
  a.user_person_type,
  a.job_code,
  a.grade_code AS band,
  a.grade_ladder_name AS comp_ladder_directorate,
  a.department_name AS cost_center_name,
  a.assignment_category,
  a.worker_category,
  a.contract_type AS permanent_temporary,
  a.hourly_or_salaried AS hourly_salaried_code,
  a.normal_hours,
  a.payment_frequency AS frequency,
  a.seniority_basis,
  a.union_name,
  a.assignment_created_by AS created_by,
  a.assignment_updated_by AS last_updated_by,
  a.insurance_policy,
  a.brand,
  a.contract_type,
  a.career_path AS career_track,
  a.insurance_company,
  a.target_rvv,
  a.target_profit_sharing AS target_plr,
  a.is_primary_assignment,
  a.is_manager,
  COALESCE(te.dt_effective_start, a.dt_assignment_started) AS dt_effective_start,
  COALESCE(te.dt_effective_end, a.dt_assignment_ended) AS dt_effective_end,
  a.dt_projected_start,
  a.ts_work_relationship_created AS ts_created,
  a.ts_work_relationship_updated AS ts_last_update,
  NOW() AS ts_load
FROM
  datalake_hr_system.assignment_snapshot AS a
LEFT JOIN
  terminated_employees AS te
    ON te.id_period_of_service = a.id_period_of_service
WHERE
  is_current_info
  OR
  (is_future_info AND NOT EXISTS (
    SELECT 1
    FROM datalake_hr_system.assignment_snapshot AS sub
    WHERE sub.id_period_of_service = a.id_period_of_service
      AND sub.is_current_info
  ))
