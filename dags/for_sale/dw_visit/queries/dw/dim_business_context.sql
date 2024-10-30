SELECT
    1 AS sk_business_context,
    'SALE' AS business_context,
    NOW() AS ts_load
UNION ALL
SELECT
    2 AS sk_business_context,
    'RENT' AS business_context,
    NOW() AS ts_load
