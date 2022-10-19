SELECT DISTINCT
    id_workflow AS sk_workflow,
    status,
    ts_workflow_started AS ts_started,
    ts_workflow_updated AS ts_updated,
    ts_workflow_ended AS ts_ended,
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
