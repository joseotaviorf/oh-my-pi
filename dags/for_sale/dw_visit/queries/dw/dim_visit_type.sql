SELECT
    1 AS sk_visit_type,
    'PRESENTIAL' AS type_name,
    NOW() AS ts_load
UNION ALL
SELECT
    2 AS sk_visit_type,
    'VIDEO' AS type_name,
    NOW() AS ts_load
