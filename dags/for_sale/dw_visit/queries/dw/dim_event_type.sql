SELECT
    DISTINCT(event_type) AS event_type,
    NOW() AS ts_load
FROM
    datalake_visit.visit_status_events
