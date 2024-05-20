SELECT 
    JobId AS id_job,
    SetId AS id_set,
    JobFamilyId AS id_job_family,
    GradeLadderId AS id_grade_ladder,
    JobCode AS job_code,
    ActiveStatus AS active_status,
    FullPartTime AS full_part_time,
    JobFunctionCode AS job_function_code,
    ManagerLevel AS manager_level,
    StandardWorkingHours AS standard_working_hours,
    StandardWorkingFrequency AS standard_working_frequency,
    StandardAnnualWorkingDuration AS standard_annual_working_duration,
    AnnualWorkingDurationUnits AS annual_working_duration_units,
    RegularTemporary AS regular_temporary,
    Name AS job_name,
    ApprovalAuthority AS approval_authority,
    SchedulingGroup AS scheduling_group,
    JobCustomerFlex AS job_customer_flex,
    validGrades AS valid_grades,
    CASE 
      WHEN MedicalCheckupRequired = 'Y'
        THEN TRUE
      ELSE FALSE
    END AS is_medical_checkup_required,
    to_date(EffectiveStartDate, 'yyyy-MM-dd') AS dt_effective_start,
    to_date(EffectiveEndDate, 'yyyy-MM-dd') AS dt_effective_end,
    to_timestamp(substr(replace(CreationDate, 'T', ' '), 0, 19), 'yyyy-MM-dd HH:mm:ss') AS ts_created,
    to_timestamp(substr(replace(LastUpdateDate, 'T', ' '), 0, 19), 'yyyy-MM-dd HH:mm:ss') AS ts_last_update,
    ts_load AS ts_load,
    year AS year,
    month AS month,
    day AS day
FROM 
  datalake_hr_system_raw.jobs