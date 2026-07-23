SELECT DISTINCT
    visit_model,
    NOW() AS ts_load
FROM
    datalake_visit.visit_schedules
