SELECT DISTINCT
    method AS entrance_type,
    NOW() AS ts_load
FROM
    datalake_visit.visits
