SELECT
    JobFamilyId AS id_job_family,
    JobFamilyName AS name_job_family,
    JobFamilyCode AS code_job_family,
    ActiveStatus AS status_active,
    JobFamilyDFF AS job_family_dff,
    EffectiveStartDate AS dt_effective_started_date,
    EffectiveEndDate AS dt_effective_ended_date,
    CreationDate AS ts_created,
    LastUpdateDate AS ts_last_updated
FROM
    datalake_hr_system_raw.job_families
