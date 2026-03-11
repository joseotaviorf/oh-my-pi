SELECT
    ed.id_event_definition AS sk_event_definition,
    ed.action_name,
    ed.reason_name,
    ed.action_name_ptb,
    ed.reason_name_ptb,
    NOW() AS ts_load
FROM
    datalake_people_core.event_definition AS ed
WHERE
    ed.is_current = TRUE
