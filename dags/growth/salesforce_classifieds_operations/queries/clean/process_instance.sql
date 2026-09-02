SELECT
    Id AS id,
    CreatedById AS id_created_by,
    LastActorId AS id_last_actor,
    LastModifiedById AS id_last_modified_by,
    ProcessDefinitionId AS id_process_definition,
    SubmittedById AS id_submitted_by,
    TargetObjectId AS id_target_object,
    Status AS status_name,
    ElapsedTimeInDays AS elapsed_time_days,
    ElapsedTimeInHours AS elapsed_time_hours,
    ElapsedTimeInMinutes AS elapsed_time_minutes,
    IsDeleted AS is_deleted,
    CompletedDate AS ts_completed,
    CreatedDate AS ts_created,
    LastModifiedDate AS ts_last_modified,
    SystemModstamp AS ts_system_mod,
    CAST(LastModifiedDate AS DATE) AS dt_updated,
    YEAR(LastModifiedDate) AS year,
    MONTH(LastModifiedDate) AS month,
    DAY(LastModifiedDate) AS day
FROM
    datalake_salesforce_classifieds_raw.processinstance
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
