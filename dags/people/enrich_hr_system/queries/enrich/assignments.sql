WITH
hr_system_workers AS (
  SELECT
    id_person,
    work_relationships,
    dt_effective
  FROM
    datalake_hr_system_clean.workers
),
work_rel_step1 AS (
  SELECT
    id_person,
    dt_effective,
    EXPLODE (work_relationships) AS work_relationships
  FROM
    hr_system_workers
),
work_rel AS (
  SELECT
    id_person,
    dt_effective,
    work_relationships['PeriodOfServiceId'] AS id_period_of_service,
    work_relationships['assignments']       AS assignments
  FROM
    work_rel_step1
),
assignments_step1 AS (
  SELECT
    id_person,
    dt_effective,
    id_period_of_service,
    EXPLODE (assignments) AS assignments
  FROM
    work_rel
),
assignments AS (
  SELECT
    id_person,
    id_period_of_service,
    dt_effective,
    assignments['AssignmentId']                AS id_assignment,
    assignments['AssignmentNumber']            AS assignment_number,
    assignments['AssignmentName']              AS assignment_name,
    assignments['ActionCode']                  AS action_code,
    assignments['ReasonCode']                  AS reason_code,
    assignments['EffectiveStartDate']          AS dt_effective_start,
    assignments['EffectiveEndDate']            AS dt_effective_end,
    assignments['EffectiveSequence']           AS effective_sequence,
    assignments['EffectiveLatestChange']       AS effective_latest_change,
    assignments['BusinessUnitId']              AS id_business_unit,
    assignments['BusinessUnitName']            AS business_unit_name,
    assignments['AssignmentType']              AS assignment_type,
    assignments['AssignmentStatusTypeId']      AS id_assignment_status_type,
    assignments['AssignmentStatusTypeCode']    AS assignment_status_type_code,
    assignments['AssignmentStatusType']        AS assignment_status_type,
    assignments['SystemPersonType']            AS system_person_type,
    assignments['UserPersonTypeId']            AS id_user_person_type,
    assignments['UserPersonType']              AS user_person_type,
    assignments['ProposedUserPersonTypeId']    AS id_proposed_user_person_type,
    assignments['ProjectedStartDate']          AS dt_projected_start,
    assignments['PrimaryFlag']                 AS primary_flag,
    assignments['PrimaryAssignmentFlag']       AS primary_assignment_flag,
    assignments['SynchronizeFromPositionFlag'] AS synchronize_from_position,
    assignments['JobId']                       AS id_job,
    assignments['JobCode']                     AS job_code,
    assignments['GradeId']                     AS id_band,
    assignments['GradeCode']                   AS band,
    assignments['GradeLadderId']               AS id_band_ladder,
    assignments['GradeLadderName']             AS band_ladder_name,
    assignments['GradeStepEligibilityFlag']    AS band_step_eligibility,
    assignments['DepartmentId']                AS id_cost_center,
    assignments['DepartmentName']              AS cost_center_name,
    assignments['WorkAtHomeFlag']              AS work_at_home,
    assignments['AssignmentCategory']          AS assignment_category,
    assignments['WorkerCategory']              AS worker_category,
    assignments['PermanentTemporary']          AS permanent_temporary,
    assignments['ManagerFlag']                 AS manager_flag,
    assignments['HourlySalariedCode']          AS hourly_salaried_code,
    assignments['NormalHours']                 AS normal_hours,
    assignments['Frequency']                   AS frequency,
    assignments['SeniorityBasis']              AS seniority_basis,
    assignments['UnionId']                     AS id_union,
    assignments['UnionName']                   AS union_name,
    assignments['InternalFloor']               AS days_experience_period_1,
    assignments['InternalOfficeNumber']        AS days_experience_period_2,
    assignments['CreatedBy']                   AS created_by,
    assignments['CreationDate']                AS ts_created,
    assignments['LastUpdatedBy']               AS last_updated_by,
    assignments['LastUpdateDate']              AS ts_last_update,
    assignments['assignmentsDFF']              AS assignments_dff
  FROM
    assignments_step1
),
assignments_dff_step1 AS (
  SELECT
    id_person,
    id_period_of_service,
    id_assignment,
    dt_effective,
    EXPLODE (assignments_dff) AS assignments_dff
  FROM
    assignments
),
assignments_dff AS (
  SELECT
    id_person,
    id_period_of_service,
    id_assignment,
    dt_effective,
    assignments_dff['temAtividadeElevadoValorAcresc'] AS has_activity_with_extra_value,
    assignments_dff['turnoDeTrabalho']                AS work_shift,
    assignments_dff['targetRvv']                      AS target_rvv,
    assignments_dff['ApoliceSeguro']                  AS insurance_policy,
    assignments_dff['EffectiveLatestChange']          AS effective_latest_change,
    assignments_dff['adicionalPorTempoDeServico']     AS additional_for_service_time,
    assignments_dff['aposentado']                     AS retired,
    assignments_dff['targetPlr']                      AS target_plr,
    assignments_dff['regimeDeJornadaDoEmpregado']     AS working_day_regime,
    assignments_dff['compensaSabado']                 AS compensates_saturday,
    assignments_dff['cargaHoraria']                   AS workload,
    assignments_dff['marcaProduto']                   AS brand,
    assignments_dff['EffectiveSequence']              AS effective_sequence,
    assignments_dff['tipoDeContrato']                 AS contract_type,
    assignments_dff['EffectiveEndDate']               AS dt_effective_end,
    assignments_dff['vinculoEmpregaticio']            AS employment_relationship,
    assignments_dff['funcionarioMarcaPonto']          AS has_clock_in,
    assignments_dff['trilha']                         AS trail,
    assignments_dff['dataFinalDaExperiencia2']        AS dt_experience_period_2,
    assignments_dff['seguradora']                     AS insurance_company,
    assignments_dff['seSimIndiqueOCodigoDaAtividade'] AS activity_code,
    assignments_dff['processoRegimeDeContratacao']    AS contracting_regime_process,
    assignments_dff['dataFinalDaExperiencia1']        AS dt_experience_period_1,
    assignments_dff['EffectiveStartDate']             AS dt_effective_start
  FROM
    assignments_dff_step1
)
SELECT DISTINCT
  -- ids
  a.id_assignment,
  -- non-ids
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
  -- non-metrics
  a.assignment_number,
  a.assignment_name,
  a.action_code,
  a.reason_code,
  a.effective_sequence,
  a.business_unit_name,
  a.assignment_type,
  a.assignment_status_type_code,
  a.assignment_status_type,
  a.system_person_type,
  a.user_person_type,
  a.job_code,
  a.band,
  a.band_ladder_name,
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
  adff.work_shift,
  adff.insurance_policy,
  adff.additional_for_service_time,
  adff.working_day_regime,
  adff.compensates_saturday,
  adff.workload,
  adff.brand,
  adff.effective_sequence AS effective_sequence_adff,
  adff.contract_type,
  adff.employment_relationship,
  adff.trail,
  adff.insurance_company,
  adff.activity_code,
  adff.contracting_regime_process,
  adff.retired,
  -- metrics
  INT(a.days_experience_period_1) AS days_experience_period_1,
  INT(a.days_experience_period_2) AS days_experience_period_2,
  FLOAT(adff.target_rvv) AS target_rvv,
  FLOAT(adff.target_plr) AS target_plr,
  BOOLEAN(a.primary_flag) AS is_primary,
  BOOLEAN(a.primary_assignment_flag) AS is_primary_assignment,
  BOOLEAN(a.manager_flag) AS is_manager,
  BOOLEAN(a.synchronize_from_position) AS has_synchronization_in_position,
  BOOLEAN(a.band_step_eligibility) AS has_band_step_eligibility,
  BOOLEAN(a.work_at_home) AS is_working_at_home,
  CASE
    WHEN adff.has_activity_with_extra_value = 'Y' THEN TRUE
    WHEN adff.has_activity_with_extra_value = 'N' THEN FALSE
  END AS has_activity_with_extra_value,
  BOOLEAN(adff.has_clock_in) AS has_clock_in,
  -- dates
  GREATEST (DATE(a.dt_effective_start), DATE(adff.dt_effective_start)) AS dt_effective_start,
  GREATEST (DATE(a.dt_effective_end), DATE(adff.dt_effective_end)) AS dt_effective_end,
  DATE(a.dt_projected_start) AS dt_projected_start,
  DATE(adff.dt_experience_period_1) AS dt_experience_period_1,
  DATE(adff.dt_experience_period_2) AS dt_experience_period_2,
  -- timestamps
  TO_TIMESTAMP(SUBSTR(REPLACE(a.ts_created, 'T', ' '), 0, 19), 'yyyy-MM-dd HH:mm:ss') AS ts_created,
  TO_TIMESTAMP(SUBSTR(REPLACE(a.ts_last_update, 'T', ' '), 0, 19), 'yyyy-MM-dd HH:mm:ss') AS ts_last_update,
  NOW() AS ts_load,
  -- partitions
  DATE_FORMAT(GREATEST (DATE(a.dt_effective_start), DATE(adff.dt_effective_start)), 'yyyy') AS year,
  DATE_FORMAT(GREATEST (DATE(a.dt_effective_start), DATE(adff.dt_effective_start)), 'MM') AS month
FROM
  assignments AS a
  LEFT JOIN 
    assignments_dff AS adff 
      ON a.id_person = adff.id_person
      AND a.id_period_of_service = adff.id_period_of_service
      AND a.id_assignment = adff.id_assignment
      AND a.dt_effective = adff.dt_effective
WHERE
  DATE_TRUNC('MONTH', GREATEST (DATE(a.dt_effective_start), DATE(adff.dt_effective_start))) > DATE_TRUNC('MONTH', DATE('{load_start_date}'))