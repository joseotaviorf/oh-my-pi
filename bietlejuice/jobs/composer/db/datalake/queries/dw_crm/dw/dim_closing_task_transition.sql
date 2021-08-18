SELECT DISTINCT
    id_transition AS sk_transition,
    origin_type,
    destination_type,
    conclusion_option,
    conclusion_context,
    contact_channel,
    status,
    ts_transitioned,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_crm_tasks_transitions.tasks_transitions
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
