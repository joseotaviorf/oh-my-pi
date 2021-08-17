SELECT DISTINCT
    tsk.id AS id_task,
    tsh.id AS id_action,
    tsh.id_user_action,
    tsk.id_assignee,
    tsk.id_house,
    tsk.id_rent_flow,
    tsk.id_origin,
    tsk.id_opened_by,
    tsk.id_tenant,
    tsk.id_negotiation,
    tsk.id_manager,
    tsk.id_owner,
    tsk.id_receiver,
    tsk.id_workgroup,
    tsh.task_status,
    tsh.action_reason,
    tsh.action_user_name,
    tsh.action_type,
    tsk.type,
    tsk.version,
    tsk.tags,
    tsk.score,
    tsk.score_factor,
    tsk.receiver_name,
    tsk.receiver_type,
    tsk.task_comment,
    tsk.origin,
    tsk.description,
    tsk.phase,
    tsk.subject,
    tsk.visit_fup,
    IF(
        tsh.action_user_name IS NULL,
        NULL,
        ROUND(
            (TO_UNIX_TIMESTAMP(LEAD(tsh.ts_action) OVER (PARTITION BY tsk.id ORDER BY tsh.ts_action),  'yyyy-MM-dd HH:mm:ss') - TO_UNIX_TIMESTAMP(tsh.ts_action, 'yyyy-MM-dd HH:mm:ss'))/3600.0,
            1
        )
    ) AS task_user_resolve_hours,
    tsk.is_resolved,
    tsh.ts_action,
    LAG(tsh.ts_action) OVER (PARTITION BY tsk.id ORDER BY tsh.ts_action) AS ts_previous_action,
    LEAD(tsh.ts_action) OVER (PARTITION BY tsk.id ORDER BY tsh.ts_action) AS ts_next_action,
    tsk.ts_created,
    tsk.ts_start,
    tsk.ts_completed,
    tsk.dt_visit,
    tsk.ts_silenced_until,
    tsk.ts_origin,
    tsk.ts_fup,
    tsh.year,
    tsh.month,
    tsh.day
FROM
    datalake_crm.tasks tsk
INNER JOIN
    datalake_crm.task_status_histories tsh
        ON tsk.id = tsh.id_task
UNION ALL
SELECT DISTINCT
    tsk.id AS id_task,
    tac.id AS id_action,
    tac.id_user_action,
    tsk.id_assignee,
    tsk.id_house,
    tsk.id_rent_flow,
    tsk.id_origin,
    tsk.id_opened_by,
    tsk.id_tenant,
    tsk.id_negotiation,
    tsk.id_manager,
    tsk.id_owner,
    tsk.id_receiver,
    tsk.id_workgroup,
    NULL AS task_status,
    NULL AS action_reason,
    tac.action_user_name,
    tac.action_type,
    tsk.type,
    tsk.version,
    tsk.tags,
    tsk.score,
    tsk.score_factor,
    tsk.receiver_name,
    tsk.receiver_type,
    tsk.task_comment,
    tsk.origin,
    tsk.description,
    tsk.phase,
    tsk.subject,
    tsk.visit_fup,
    IF(
        tac.action_user_name IS NULL,
        NULL,
        ROUND(
            (TO_UNIX_TIMESTAMP(LEAD(tac.ts_action) OVER (PARTITION BY tsk.id ORDER BY tac.ts_action),  'yyyy-MM-dd HH:mm:ss') - TO_UNIX_TIMESTAMP(tac.ts_action, 'yyyy-MM-dd HH:mm:ss'))/3600.0,
            1
        )
    ) AS task_user_resolve_hours,
    tsk.is_resolved,
    tac.ts_action,
    LAG(tac.ts_action) OVER (PARTITION BY tsk.id ORDER BY tac.ts_action) AS ts_previous_action,
    LEAD(tac.ts_action) OVER (PARTITION BY tsk.id ORDER BY tac.ts_action) AS ts_next_action,
    tsk.ts_created,
    tsk.ts_start,
    tsk.ts_completed,
    tsk.dt_visit,
    tsk.ts_silenced_until,
    tsk.ts_origin,
    tsk.ts_fup,
    tac.year,
    tac.month,
    tac.day
FROM
    datalake_crm.tasks tsk
INNER JOIN
    datalake_crm.tasks_actions tac
        ON tsk.id=tac.id_task