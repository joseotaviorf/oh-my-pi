SELECT DISTINCT
    business_context,
    NOW() AS ts_load
FROM
    datalake_visit.visits
