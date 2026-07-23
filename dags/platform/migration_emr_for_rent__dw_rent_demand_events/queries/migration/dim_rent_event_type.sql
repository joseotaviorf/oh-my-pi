SELECT
      1 AS sk_event_type,
      'VISIT_BOOKED' AS event_name,
      'VB' AS abbreviation,
      'BOOKING' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      2 AS sk_event_type,
      'VISIT_COMPLETED' AS event_name,
      'VC' AS abbreviation,
      'BOOKING' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      3 AS sk_event_type,
      'OFFER_SUBMITTED' AS event_name,
      'OS' AS abbreviation,
      'OFFER' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      4 AS sk_event_type,
      'OFFER_ACCEPTED' AS event_name,
      'OA' AS abbreviation,
      'OFFER' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      5 AS sk_event_type,
      'EVALUATION STARTED' AS event_name,
      'ES' AS abbreviation,
      'PROPOSAL' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      6 AS sk_event_type,
      'EVALUATION POSITIVE' AS event_name,
      'EP' AS abbreviation,
      'PROPOSAL' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      7 AS sk_event_type,
      'DOCUMENT_SENT' AS event_name,
      'DS' AS abbreviation,
      'PROPOSAL' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      8 AS sk_event_type,
      'CREDIT_APPROVED' AS event_name,
      'CA' AS abbreviation,
      'PROPOSAL' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      9 AS sk_event_type,
      'CONTRACT_SIGNED' AS event_name,
      'CS' AS abbreviation,
      'CONTRACT' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      10 AS sk_event_type,
      'CONTRACT_CREATED' AS event_name,
      'CC' AS abbreviation,
      'CONTRACT' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      11 AS sk_event_type,
      'VISIT_REQUESTED' AS event_name,
      'VR' AS abbreviation,
      'VISIT' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      12 AS sk_event_type,
      'VISIT_SCHEDULED' AS event_name,
      'VS' AS abbreviation,
      'VISIT' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      13 AS sk_event_type,
      'VISIT_RESCHEDULED' AS event_name,
      'VRS' AS abbreviation,
      'VISIT' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
      14 AS sk_event_type,
      'VISIT_DONE' AS event_name,
      'VD' AS abbreviation,
      'VISIT' AS stage,
      NOW() AS ts_load
  UNION ALL
  SELECT
    15 AS sk_event_type,
    'ADVANCE_PAYMENT_CREATED' AS event_name,
    'APC' AS abbreviation,
    'ADVANCE_PAYMENT' AS stage,
    NOW() AS ts_load
  UNION ALL
  SELECT
    16 AS sk_event_type,
    'ADVANCE_PAYMENT_PENDING' AS event_name,
    'APP' AS abbreviation,
    'ADVANCE_PAYMENT' AS stage,
    NOW() AS ts_load
  UNION ALL
  SELECT
    17 AS sk_event_type,
    'ADVANCE_PAYMENT_PROCESSING' AS event_name,
    'APPR' AS abbreviation,
    'ADVANCE_PAYMENT' AS stage,
    NOW() AS ts_load
  UNION ALL
  SELECT
    18 AS sk_event_type,
    'ADVANCE_PAYMENT_PAID' AS event_name,
    'APPD' AS abbreviation,
    'ADVANCE_PAYMENT' AS stage,
    NOW() AS ts_load
  UNION ALL
  SELECT
    19 AS sk_event_type,
    'ADVANCE_PAYMENT_CANCELED' AS event_name,
    'APCL' AS abbreviation,
    'ADVANCE_PAYMENT' AS stage,
    NOW() AS ts_load
  UNION ALL
  SELECT
    20 AS sk_event_type,
    'ADVANCE_PAYMENT_PROCESSING_REFUND' AS event_name,
    'APPRF' AS abbreviation,
    'ADVANCE_PAYMENT' AS stage,
    NOW() AS ts_load
  UNION ALL
  SELECT
    21 AS sk_event_type,
    'ADVANCE_PAYMENT_REFUNDED' AS event_name,
    'APRF' AS abbreviation,
    'ADVANCE_PAYMENT' AS stage,
    NOW() AS ts_load
  UNION ALL
  SELECT
    22 AS sk_event_type,
    'ADVANCE_PAYMENT_CHARGEBACK' AS event_name,
    'APCB' AS abbreviation,
    'ADVANCE_PAYMENT' AS stage,
    NOW() AS ts_load
  UNION ALL
  SELECT
    23 AS sk_event_type,
    'ADVANCE_PAYMENT_FINISHED' AS event_name,
    'APF' AS abbreviation,
    'ADVANCE_PAYMENT' AS stage,
    NOW() AS ts_load
  UNION ALL
  SELECT
    24 AS sk_event_type,
    'ADVANCE_PAYMENT_RETAINED' AS event_name,
    'APRT' AS abbreviation,
    'ADVANCE_PAYMENT' AS stage,
    NOW() AS ts_load