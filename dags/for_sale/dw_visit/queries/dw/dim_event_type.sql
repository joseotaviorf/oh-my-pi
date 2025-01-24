SELECT
    DISTINCT(event_type) AS event_name,
    NOW() AS ts_load
FROM
    datalake_visit.visit_status_events
