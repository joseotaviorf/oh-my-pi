SELECT DISTINCT
    business_model,
    NOW() AS ts_load
FROM
    datalake_visit.visits
