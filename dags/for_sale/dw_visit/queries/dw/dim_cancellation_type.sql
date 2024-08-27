SELECT
  1 AS sk_cancellation_type,
  'PERSON_NOT_INTERESTED_ON_THIS_PROPERTY_OR_ON_THIS_VISIT' AS reason,
  'CANCELED_BY_TENANT_NOT_INTERESTED' AS old_reason,
  'DEMAND' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  2 AS sk_cancellation_type,
  'PERSON_NOT_INTERESTED_ON_THIS_PROPERTY_OR_ON_THIS_VISIT' AS reason,
  'CANCELED_AGENT_CAN_NOT_ATTEND' AS old_reason,
  'AGENT' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  3 AS sk_cancellation_type,
  'PERSON_SCHEDULED_FOR_ANOTHER_TIME' AS reason,
  'CANCELED_SCHEDULED_OTHER_TIME' AS old_reason,
  'DEMAND' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  4 AS sk_cancellation_type,
  'PERSON_CANNOT_ATTEND' AS reason,
  'CANCELED_BY_TENANT_CAN_NOT_ATTEND' AS old_reason,
  'DEMAND' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  5 AS sk_cancellation_type,
  'PERSON_CANNOT_ATTEND' AS reason,
  'CANCELED_OWNER_CAN_NOT_ATTEND' AS old_reason,
  'SUPPLY' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  6 AS sk_cancellation_type,
  'PERSON_CANNOT_ATTEND' AS reason,
  'CANCELED_AGENT_CAN_NOT_ATTEND' AS old_reason,
  'AGENT' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  7 AS sk_cancellation_type,
  'PERSON_DOESNT_WANT_5A' AS reason,
  'CANCELED_CLIENT_GAVE_UP' AS old_reason,
  'DEMAND' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  8 AS sk_cancellation_type,
  'PERSON_DOESNT_WANT_5A' AS reason,
  'OTHER' AS old_reason,
  'SUPPLY' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  9 AS sk_cancellation_type,
  'VISIT_OCCURRED_AT_A_DIFFERENT_TIME' AS reason,
  'CANCELED_SCHEDULED_OTHER_TIME' AS old_reason,
  'DEMAND' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  10 AS sk_cancellation_type,
  'PERSON_IDENTIFIED_LISTING_AS_INACCURATE_OR_INCOMPLETE' AS reason,
  'CANCELED_BY_OUT_OF_DATE_AD' AS old_reason,
  'DEMAND' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  11 AS sk_cancellation_type,
  'PERSON_HAD_ISSUES_WITH_AGENT' AS reason,
  'OTHER' AS old_reason,
  'DEMAND' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  12 AS sk_cancellation_type,
  'PERSON_HAD_ISSUES_WITH_AGENT' AS reason,
  'OTHER' AS old_reason,
  'SUPPLY' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  13 AS sk_cancellation_type,
  'QUINTO_ANDAR_CANNOT_CONTACT_ONE_OF_THE_PARTIES' AS reason,
  'KEY_HOLDER_AGENT_NOT_AVAILABLE' AS old_reason,
  'DEMAND' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  14 AS sk_cancellation_type,
  'QUINTO_ANDAR_CANNOT_CONTACT_ONE_OF_THE_PARTIES' AS reason,
  'CANCELED_OWNER_UNREACHABLE' AS old_reason,
  'SUPPLY' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  15 AS sk_cancellation_type,
  'PROPERTY_TEMPORARILY_UNAVAILABLE' AS reason,
  'CANCELED_PROPERTY_UNAVAILABLE' AS old_reason,
  'SUPPLY' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  16 AS sk_cancellation_type,
  'PROPERTY_OR_PERSON_INDEFINITELY_UNAVAILABLE' AS reason,
  'CANCELED_PROPERTY_UNAVAILABLE' AS old_reason,
  'SUPPLY' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  17 AS sk_cancellation_type,
  'PROPERTY_OR_PERSON_INDEFINITELY_UNAVAILABLE' AS reason,
  'CANCELED_BY_TENANT_NOT_INTERESTED' AS old_reason,
  'DEMAND' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  18 AS sk_cancellation_type,
  'PROPERTY_ON_HOLD_FOR_ANOTHER_PROSPECT' AS reason,
  'CANCELED_PROPERTY_SUSPENDED_ADVANCED_NEGOTIATIONS' AS old_reason,
  'SUPPLY' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  19 AS sk_cancellation_type,
  'PROPERTY_RESERVED' AS reason,
  'CANCELED_HOUSE_RESERVED' AS old_reason,
  'SUPPLY' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  20 AS sk_cancellation_type,
  'PERSON_DOESNT_WANT_TO_WORK_ON_THIS_LOCATION' AS reason,
  'CANCELED_AGENT_VISIT_TOO_FAR' AS old_reason,
  'AGENT' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  21 AS sk_cancellation_type,
  'CONSEQUENCE_MANAGEMENT' AS reason,
  'OTHER' AS old_reason,
  'DEMAND' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  22 AS sk_cancellation_type,
  'CONSEQUENCE_MANAGEMENT' AS reason,
  'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT' AS old_reason,
  'SUPPLY' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  23 AS sk_cancellation_type,
  'CONSEQUENCE_MANAGEMENT' AS reason,
  'CANCELED_CANT_FIND_ANOTHER_AGENT' AS old_reason,
  'AGENT' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  24 AS sk_cancellation_type,
  'AGENT_TRANSFER_FAILED_TO_FIND_ANOTHER_AGENT' AS reason,
  'CANCELED_CANT_FIND_ANOTHER_AGENT' AS old_reason,
  'AGENT' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  25 AS sk_cancellation_type,
  'Request_expired' AS reason,
  'CANCELED_BY_TENANT_NOT_INTERESTED' AS old_reason,
  'DEMAND' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  26 AS sk_cancellation_type,
  'Request_expired' AS reason,
  'CANCELED_OWNER_UNREACHABLE' AS old_reason,
  'SUPPLY' AS on_behalf_of,
  NOW() AS ts_load
UNION ALL
  SELECT
  27 AS sk_cancellation_type,
  'Request_expired' AS reason,
  'OTHER' AS old_reason,
  'AGENT' AS on_behalf_of,
  NOW() AS ts_load
