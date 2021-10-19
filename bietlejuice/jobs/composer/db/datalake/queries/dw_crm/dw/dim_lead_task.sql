-- TO DO: After finishing CRM migration, it is necessary to rename columns following our Naming Conventions
SELECT
    id_task AS sk_task,
    score_factor,
    version,
    origin,
    type,
    description,
    subject,
    CAST(titles AS STRING) AS titles,
    CAST(workgroups AS STRING) AS workgroups,
    hours_task_started_to_completed AS hours_task_start_to_completed,
    is_resolved AS flg_solved,
    is_task_auto_completed,
    ts_started AS ts_start,
    ts_completed,
    ts_silenced_until,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_crm_tasks_flows.tasks_actions_resolutions_flow
WHERE
    type IN ('ConverterLead', 'ConverterLeadPrioritario')
    AND year = {year}
    AND month = {month}
    AND day = {day}