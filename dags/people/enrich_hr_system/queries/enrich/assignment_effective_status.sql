WITH
terminated_employees AS (
  SELECT
    wr.PeriodOfServiceId AS id_period_of_service,
    a.AssignmentNumber AS assignment_number,
    a.AssignmentStatusType AS assignment_status_type,
    a.AssignmentStatusTypeCode AS assignment_status_type_code,
    a.ActionCode AS action_code,
    a.ReasonCode AS reason_code,
    a.EffectiveStartDate AS dt_effective_start,
    a.EffectiveEndDate AS dt_effective_end,
    wr.TerminationDate AS dt_termination
  FROM
    datalake_hr_system_clean.workers AS w
  LATERAL VIEW
    EXPLODE(w.work_relationships) AS wr
  LATERAL VIEW
    EXPLODE(wr.assignments) AS a
  WHERE
    wr.WorkerType <> 'P'
    AND a.AssignmentStatusType = 'INACTIVE'
    AND w.dt_effective >= REPLACE('{load_start_date}', '-', '')
  QUALIFY
    DENSE_RANK() OVER (PARTITION BY id_period_of_service ORDER BY dt_effective_start DESC) = 1
),
ranked_assignments AS (
  SELECT
    id_assignment,
    id_person,
    id_period_of_service,
    id_business_unit,
    id_assignment_status_type,
    id_user_person_type,
    id_proposed_user_person_type,
    id_job,
    id_band,
    id_band_ladder,
    id_cost_center,
    id_union,
    assignment_number,
    assignment_name,
    CASE
      WHEN dt_effective_start > DATE('{load_start_date}') THEN 'future'
      WHEN dt_effective_start <= DATE('{load_start_date}')
        AND dt_effective_end >= DATE('{load_start_date}') THEN 'current'
    END AS effective_state,
    action_code,
    reason_code,
    effective_sequence,
    business_unit_name,
    assignment_type,
    assignment_status_type_code,
    assignment_status_type,
    system_person_type,
    user_person_type,
    job_code,
    band,
    comp_ladder_directorate,
    cost_center_name,
    assignment_category,
    worker_category,
    permanent_temporary,
    hourly_salaried_code,
    normal_hours,
    frequency,
    seniority_basis,
    union_name,
    created_by,
    last_updated_by,
    work_shift,
    insurance_policy,
    additional_for_service_time,
    working_day_regime,
    compensates_saturday,
    workload,
    brand,
    effective_sequence_adff,
    contract_type,
    employment_relationship,
    career_track,
    insurance_company,
    activity_code,
    contracting_regime_process,
    retired,
    days_experience_period_1,
    days_experience_period_2,
    target_rvv,
    target_plr,
    is_primary,
    is_primary_assignment,
    is_manager,
    has_synchronization_in_position,
    has_band_step_eligibility,
    is_working_at_home,
    has_activity_with_extra_value,
    has_clock_in,
    dt_effective_start,
    dt_effective_end,
    dt_projected_start,
    dt_experience_period_1,
    dt_experience_period_2,
    ts_created,
    ts_last_update,
    DENSE_RANK() OVER (
      PARTITION BY id_period_of_service,
        CASE
          WHEN dt_effective_start <= DATE('{load_start_date}') AND dt_effective_end >= DATE('{load_start_date}')
          THEN 'current' ELSE 'future'
        END
      ORDER BY dt_effective_start DESC, ts_last_update DESC
    ) AS effective_state_ranked
  FROM
    datalake_hr_system.assignments
  WHERE
    dt_effective_end >= DATE('{load_start_date}')
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
  a.id_band,
  a.id_band_ladder,
  a.id_cost_center,
  a.id_union,
  a.assignment_number,
  a.assignment_name,
  effective_state,
  COALESCE(te.action_code, a.action_code) AS action_code,
  COALESCE(te.reason_code, a.reason_code) AS reason_code,
  a.effective_sequence,
  a.business_unit_name,
  a.assignment_type,
  COALESCE(te.assignment_status_type_code, a.assignment_status_type_code) AS assignment_status_type_code,
  COALESCE(te.assignment_status_type, a.assignment_status_type) AS assignment_status_type,
  a.system_person_type,
  a.user_person_type,
  a.job_code,
  a.band,
  a.comp_ladder_directorate,
  a.cost_center_name,
  a.assignment_category,
  a.worker_category,
  a.permanent_temporary,
  a.hourly_salaried_code,
  a.normal_hours,
  a.frequency,
  a.seniority_basis,
  a.union_name,
  a.created_by,
  a.last_updated_by,
  a.work_shift,
  a.insurance_policy,
  a.additional_for_service_time,
  a.working_day_regime,
  a.compensates_saturday,
  a.workload,
  a.brand,
  a.effective_sequence_adff,
  a.contract_type,
  a.employment_relationship,
  a.career_track,
  a.insurance_company,
  a.activity_code,
  a.contracting_regime_process,
  a.retired,
  a.days_experience_period_1,
  a.days_experience_period_2,
  a.target_rvv,
  a.target_plr,
  a.is_primary,
  a.is_primary_assignment,
  a.is_manager,
  a.has_synchronization_in_position,
  a.has_band_step_eligibility,
  a.is_working_at_home,
  a.has_activity_with_extra_value,
  a.has_clock_in,
  COALESCE(te.dt_effective_start, a.dt_effective_start) AS dt_effective_start,
  COALESCE(te.dt_effective_end, a.dt_effective_end) AS dt_effective_end,
  a.dt_projected_start,
  a.dt_experience_period_1,
  a.dt_experience_period_2,
  a.ts_created,
  a.ts_last_update,
  NOW() AS ts_load
FROM
  ranked_assignments AS a
LEFT JOIN
  terminated_employees AS te
    ON te.id_period_of_service = a.id_period_of_service
WHERE
  (a.effective_state = 'current' AND a.effective_state_ranked = 1)
  OR
  (a.effective_state = 'future' AND a.effective_state_ranked = 1 AND NOT EXISTS (
    SELECT 1
    FROM ranked_assignments AS sub
    WHERE sub.id_period_of_service = a.id_period_of_service
      AND sub.effective_state = 'current'
  ))
