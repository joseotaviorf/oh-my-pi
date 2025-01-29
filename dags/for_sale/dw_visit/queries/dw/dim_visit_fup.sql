SELECT DISTINCT
    visit_fup,
    NOW() AS ts_load
FROM
    datalake_visit.visit_schedules
