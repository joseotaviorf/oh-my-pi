SELECT DISTINCT
    computed_status AS status_name,
    NOW() AS ts_load
FROM
    datalake_visit.visits
