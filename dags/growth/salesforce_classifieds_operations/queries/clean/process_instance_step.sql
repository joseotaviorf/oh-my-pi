SELECT
    Id AS id,
    ActorId AS id_actor,
    CreatedById AS id_created_by,
    OriginalActorId AS id_original_actor,
    ProcessInstanceId AS id_process_instance,
    StepNodeId AS id_step_node,
    Comments AS comments,
    StepStatus AS step_status_name,
    ElapsedTimeInDays AS elapsed_time_days,
    ElapsedTimeInHours AS elapsed_time_hours,
    ElapsedTimeInMinutes AS elapsed_time_minutes,
    CreatedDate AS ts_created,
    SystemModstamp AS ts_system_mod,
    CAST(CreatedDate AS DATE) AS dt_updated,
    YEAR(CreatedDate) AS year,
    MONTH(CreatedDate) AS month,
    DAY(CreatedDate) AS day
FROM
    datalake_salesforce_classifieds_raw.processinstancestep
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
