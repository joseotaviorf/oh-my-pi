SELECT DISTINCT
    schedule_origin AS origin_name,
    NOW() AS ts_load
FROM
    datalake_visit.visit_schedules
