SELECT
    1 AS sk_event_type,
    'VISIT_REQUESTED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    2 AS sk_event_type,
    'VISIT_REGISTERED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    3 AS sk_event_type,
    'ANSWER_CONFIRMED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    4 AS sk_event_type,
    'ANSWER_REJECTED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    5 AS sk_event_type,
    'VISIT_BOOKED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    6 AS sk_event_type,
    'VISIT_RESCHEDULED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    7 AS sk_event_type,
    'VISIT_REQUEST_CANCELED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    8 AS sk_event_type,
    'VISIT_CANCELED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    9 AS sk_event_type,
    'VISIT_DONE' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    10 AS sk_event_type,
    'VISIT_UNSUCCESSFUL' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    11 AS sk_event_type,
    'FOLLOW_UP_COLLECTED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    12 AS sk_event_type,
    'VISIT_CONFIRMED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    13 AS sk_event_type,
    'VISIT_FITTED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    14 AS sk_event_type,
    'VISIT_SCHEDULED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    15 AS sk_event_type,
    'VISIT_CONTESTED' AS event_name,
    NOW() AS ts_load
UNION ALL
SELECT
    16 AS sk_event_type,
    'ANSWER_PENDING' AS event_name,
    NOW() AS ts_load
