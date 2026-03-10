SELECT
    ed.id_event_definition AS sk_event_definition,
    ed.action_name,
    ed.reason_name,
    ed.action_name_ptb,
    ed.reason_name_ptb,
    CASE
        WHEN ed.reason_code IN (
            'CMP_MERI',
            'CMP_PROM',
            'PER_PROMOTION'
        ) THEN TRUE
        ELSE FALSE
    END AS is_career_progression,
    NOW() AS ts_load
FROM
    datalake_people.event_definition AS ed
WHERE
    ed.is_current = TRUE