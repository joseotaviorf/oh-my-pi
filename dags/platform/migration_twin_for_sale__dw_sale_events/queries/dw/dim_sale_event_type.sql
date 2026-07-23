SELECT
    1 AS sk_event_type,
    'VISIT_BOOKED' AS event_name,
    'VB' AS abbreviation,
    'BOOKING' AS stage
UNION ALL
SELECT
    2 AS sk_event_type,
    'VISIT_COMPLETED' AS event_name,
    'VC' AS abbreviation,
    'BOOKING' AS stage
UNION ALL
SELECT
    3 AS sk_event_type,
    'OFFER_SUBMITTED' AS event_name,
    'OS' AS abbreviation,
    'OFFER' AS stage
UNION ALL
SELECT
    4 AS sk_event_type,
    'OFFER_ACCEPTED' AS event_name,
    'OA' AS abbreviation,
    'OFFER' AS stage
UNION ALL
SELECT
    5 AS sk_event_type,
    'SALE_AGREEMENT_CREATED' AS event_name,
    'SAC' AS abbreviation,
    'CLOSING' AS stage
UNION ALL
SELECT
    6 AS sk_event_type,
    'SALE_AGREEMENT_SIGNED' AS event_name,
    'CCV' AS abbreviation,
    'CLOSING' AS stage
UNION ALL
SELECT
    7 AS sk_event_type,
    'VISIT_CANCELLED' AS event_name,
    'BC' AS abbreviation,
    'BOOKING' AS stage
UNION ALL
SELECT
    8 AS sk_event_type,
    'OFFER_REJECTED' AS event_name,
    'OR' AS abbreviation,
    'OFFER' AS stage
