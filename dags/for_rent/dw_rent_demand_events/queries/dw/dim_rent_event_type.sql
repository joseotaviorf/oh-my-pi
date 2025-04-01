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