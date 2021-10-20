SELECT
    turf.id_task AS sk_task,
    turf.id_receiver AS sk_receiver,
    COALESCE(CAST(turf.id_origin AS BIGINT), -1) AS sk_origin,
    turf.id_assignee AS sk_assignee,
    turf.id_user_action AS sk_user_action,
    turf.id_origin AS sk_lead,
    turf.id_start_date AS sk_start_date,
    turf.id_completed_date AS sk_completed_date,
    turf.id_action_date AS sk_action_date,
    turf.id_task_user_start_date AS sk_task_action_start_date,
    turf.id_task_user_end_date AS sk_task_action_end_date,
    turf.action_user_name,
    turf.action_type,
    turf.task_user_type AS task_action_type,
    turf.task_user_resolve_hours AS task_user_action_resolve_hours,
    turf.ts_action,
    turf.ts_task_user_start AS ts_task_action_start,
    turf.ts_task_user_end AS ts_task_action_end,
    NOW() AS ts_load,
    turf.year,
    turf.month,
    turf.day
FROM
    datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
WHERE
    turf.type IN ('ConverterLead', 'ConverterLeadPrioritario')
    AND turf.year = {year}
    AND turf.month = {month}
    AND turf.day = {day}