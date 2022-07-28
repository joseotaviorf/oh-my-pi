-- TO DO: After finishing CRM migration, it is necessary to rename columns following our Naming Conventions
WITH last_updated_task AS (
    SELECT
        id_task,
        MAX(DATE(CONCAT(year,'-',month,'-',day))) AS dt_last_updated
    FROM
        datalake_crm_tasks_flows.tasks_actions_resolutions_flow
    GROUP BY 1
)
SELECT
    tarf.id_task AS sk_task,
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
    NOW() AS ts_load
FROM
    datalake_crm_tasks_flows.tasks_actions_resolutions_flow tarf
JOIN
    last_updated_task lut
        ON tarf.id_task = lut.id_task
        AND DATE(CONCAT(tarf.year,'-',tarf.month,'-',tarf.day)) = lut.dt_last_updated
WHERE
    id_workgroup IN (
        'DEP_MEDIACAO_POS_CONTRATO_ID',
        'PROTECTION_CUSTOMERS',
        'PROTECTION_PARTNERS')
    AND type = 'Manual'