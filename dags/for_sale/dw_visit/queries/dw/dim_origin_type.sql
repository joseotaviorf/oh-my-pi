SELECT
    1 AS sk_origin_type,
    'REQUEST' AS origin_name,
    NOW() AS ts_load
UNION ALL
SELECT
    2 AS sk_origin_type,
    'RESCHEDULE' AS origin_name,
    NOW() AS ts_load
