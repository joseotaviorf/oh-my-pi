SELECT
    1 AS sk_visit_model,
    'STANDARD' AS visit_model,
    NOW() AS ts_load
UNION ALL
SELECT
    2 AS visit_model,
    'REGISTERED' AS visit_model,
    NOW() AS ts_load
UNION ALL
SELECT
    3 AS sk_visit_model,
    'FITTED' AS visit_model,
    NOW() AS ts_load
