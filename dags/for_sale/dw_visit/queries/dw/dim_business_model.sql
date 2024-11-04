SELECT
    1 AS sk_business_model,
    '1P' AS business_model,
    NOW() AS ts_load
UNION ALL
SELECT
    2 AS sk_business_model,
    '3P' AS business_model,
    NOW() AS ts_load
