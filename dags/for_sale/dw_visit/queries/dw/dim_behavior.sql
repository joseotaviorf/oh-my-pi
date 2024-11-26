SELECT
    1 AS sk_behavior_type,
    'CONFIRMATION_SUPPLY' AS behavior_type,
    NOW() AS ts_load
UNION ALL
SELECT
    2 AS sk_behavior_type,
    'CONFIRMATION_TENANT_LIVING' AS behavior_type,
    NOW() AS ts_load
UNION ALL
SELECT
    3 AS sk_behavior_type,
    'INSTANT_BOOKING' AS behavior_type,
    NOW() AS ts_load
