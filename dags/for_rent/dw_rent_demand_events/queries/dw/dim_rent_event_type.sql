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
      'EVALUATION STARTED' AS event_name,
      'ES' AS abbreviation,
      'PROPOSAL' AS stage
  UNION ALL
  SELECT
      6 AS sk_event_type,
      'EVALUATION POSITIVE' AS event_name,
      'EP' AS abbreviation,
      'PROPOSAL' AS stage
  UNION ALL
  SELECT
      7 AS sk_event_type,
      'DOCUMENT_SENT' AS event_name,
      'DS' AS abbreviation,
      'PROPOSAL' AS stage
  UNION ALL
  SELECT
      8 AS sk_event_type,
      'CREDIT_APPROVED' AS event_name,
      'CA' AS abbreviation,
      'PROPOSAL' AS stage
  UNION ALL
  SELECT
      9 AS sk_event_type,
      'CONTRACT_SIGNED' AS event_name,
      'CS' AS abbreviation,
      'CONTRACT' AS stage