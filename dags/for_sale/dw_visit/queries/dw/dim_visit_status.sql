SELECT
    1 AS sk_visit_status,
    'REQUESTED' AS status_name,
    NOW() AS ts_load
UNION ALL
SELECT
    2 AS sk_visit_status,
    'CONFIRMED' AS status_name,
    NOW() AS ts_load
UNION ALL
SELECT
    3 AS sk_visit_status,
    'DONE' AS status_name,
    NOW() AS ts_load
UNION ALL
SELECT
    4 AS sk_visit_status,
    'REQUEST_CANCELED' AS status_name,
    NOW() AS ts_load
UNION ALL
SELECT
    5 AS sk_visit_status,
    'CANCELED' AS status_name,
    NOW() AS ts_load
UNION ALL
SELECT
    6 AS sk_visit_status,
    'UNSUCCESSFUL' AS status_name,
    NOW() AS ts_load
