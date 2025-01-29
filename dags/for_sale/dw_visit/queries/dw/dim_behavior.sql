SELECT
    DISTINCT(behavior) AS behavior_type,
    NOW() AS ts_load
FROM
    datalake_visit.visits
