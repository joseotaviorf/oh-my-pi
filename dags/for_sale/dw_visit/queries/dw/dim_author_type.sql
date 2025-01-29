SELECT DISTINCT
    author_user_type AS author_type,
    author_user_role,
    on_behalf_of,
    channel,
    NOW() AS ts_load
FROM
    datalake_visit.visit_status_events
