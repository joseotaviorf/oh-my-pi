SELECT DISTINCT
    id_transition AS sk_transition,
    id_workflow AS sk_workflow,
    id_task_from AS sk_origin_task,
    id_task_to AS sk_destination_task,
    COALESCE(CAST(date_format(ts_transitioned,'yyyyMMdd') AS INTEGER), CAST('-1' AS INTEGER)) AS sk_transitioned_date,
    is_end_of_workflow,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_crm.workflows_transitions
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
