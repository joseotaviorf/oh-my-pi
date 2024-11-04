SELECT
    1 AS sk_entrance_type,
    'Front Door' AS entrance_type,
    NOW() AS ts_load
UNION ALL
SELECT
    2 AS sk_entrance_type,
    'Keys with Agent' AS entrance_type,
    NOW() AS ts_load
UNION ALL
SELECT
    3 AS sk_entrance_type,
    'Lockbox' AS entrance_type,
    NOW() AS ts_load
UNION ALL
SELECT
    4 AS sk_entrance_type,
    'Password' AS entrance_type,
    NOW() AS ts_load
UNION ALL
SELECT
    5 AS sk_entrance_type,
    'Keys Locker' AS entrance_type,
    NOW() AS ts_load
UNION ALL
SELECT
    6 AS sk_entrance_type,
    'Owner Present' AS entrance_type,
    NOW() AS ts_load
