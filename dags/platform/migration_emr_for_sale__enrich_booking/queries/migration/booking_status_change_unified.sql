WITH old_filtered_schedule AS (
  SELECT
    bsc.id_booking,
    MIN(bsc.ts_created) AS ts_first_event
  FROM datalake_ebdb_clean.booking_status_change AS bsc
  LEFT JOIN datalake_ebdb_clean.booking AS b
    ON b.id = bsc.id_booking
  WHERE
    (
      b.type <> 'Visita'
    )
    OR (
      b.type = 'Visita' AND CAST(bsc.ts_created AS DATE) < '2025-09-01'
    )
  GROUP BY
    1
), old_status AS (
  SELECT
    id_booking,
    id_user,
    status,
    reason,
    reason_enum,
    reason_category,
    type,
    ts_created,
    ts_first_event
  FROM (
    SELECT
      bsc.id_booking,
      bsc.id_user,
      bsc.status,
      REPLACE(bsc.reason, '\n', '') AS reason,
      bsc.reason_enum,
      acrc.name AS reason_category,
      b.type,
      bsc.ts_created,
      f.ts_first_event,
      ROW_NUMBER() OVER (PARTITION BY bsc.id_booking, bsc.status ORDER BY bsc.id DESC) AS _w,
      bsc.id
    FROM old_filtered_schedule AS f
    LEFT JOIN datalake_ebdb_clean.booking_status_change AS bsc
      ON f.id_booking = bsc.id_booking
    LEFT JOIN datalake_ebdb_clean.booking AS b
      ON b.id = bsc.id_booking
    LEFT JOIN datalake_ebdb_clean.appointment_change_reason_category AS acrc
      ON acrc.id = bsc.id_reason_category
  ) AS _t
  WHERE
    _w = 1
), new_filtered_schedule AS (
  SELECT
    id_visit,
    id_schedule,
    LEAD(id_schedule) OVER (PARTITION BY id_visit ORDER BY MIN(ts_created)) AS id_succeed_schedule,
    LEAD(MIN_BY(id_author_user, ts_created)) OVER (PARTITION BY id_visit ORDER BY MIN(ts_created)) AS id_succeed_user,
    MIN(ts_created) FILTER(WHERE
      event_type = 'VISIT_FITTED') AS ts_visit_fitted,
    MIN(ts_created) FILTER(WHERE
      event_type = 'VISIT_REGISTERED') AS ts_visit_registered,
    MIN(ts_created) AS ts_first_event
  FROM datalake_ebdb_clean.visit_status_log
  WHERE
    CAST(ts_created AS DATE) >= '2024-11-01'
  GROUP BY
    1,
    2
), new_requested_status AS (
  SELECT
    id_booking,
    id_user,
    status,
    reason,
    reason_enum,
    reason_category,
    type,
    ts_created,
    ts_first_event
  FROM (
    SELECT
      vsl.id_schedule AS id_booking,
      vsl.id_author_user AS id_user,
      'AguardandoConfirmacao' AS status,
      CASE
        WHEN NOT f.ts_visit_fitted IS NULL
        THEN 'Visita extra de encaixe'
        WHEN vsl.channel = 'AGENT_PWA'
        THEN 'Visita marcada pelo app de corretores'
        ELSE 'Agendamento via site'
      END AS reason,
      reason AS reason_enum,
      NULL AS reason_category,
      'Visita' AS type,
      vsl.ts_created,
      f.ts_first_event,
      ROW_NUMBER() OVER (PARTITION BY f.id_schedule ORDER BY id_visit_status_log DESC) AS _w,
      f.id_schedule,
      id_visit_status_log
    FROM new_filtered_schedule AS f
    LEFT JOIN datalake_ebdb_clean.visit_status_log AS vsl
      ON f.id_schedule = vsl.id_schedule
    WHERE
      vsl.event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED')
      AND CAST(f.ts_first_event AS DATE) >= '2025-09-01'
  ) AS _t
  WHERE
    _w = 1
), new_confirmed_status AS (
  SELECT
    id_booking,
    id_user,
    status,
    reason,
    reason_enum,
    reason_category,
    type,
    ts_created,
    ts_first_event
  FROM (
    SELECT
      vsl.id_schedule AS id_booking,
      vsl.id_author_user AS id_user,
      'Marcado' AS status,
      IF(NOT ts_visit_registered IS NULL, 'AGENT_SCHEDULE_REALIZED', NULL) AS reason,
      IF(NOT ts_visit_registered IS NULL, 'AGENT_SCHEDULE_REALIZED', NULL) AS reason_enum,
      IF(NOT ts_visit_registered IS NULL, 'Other', NULL) AS reason_category,
      'Visita' AS type,
      ts_created,
      f.ts_first_event,
      ROW_NUMBER() OVER (PARTITION BY f.id_schedule ORDER BY id_visit_status_log DESC) AS _w,
      f.id_schedule,
      id_visit_status_log
    FROM new_filtered_schedule AS f
    LEFT JOIN datalake_ebdb_clean.visit_status_log AS vsl
      ON f.id_schedule = vsl.id_schedule
    WHERE
      event_type = 'VISIT_CONFIRMED' AND CAST(f.ts_first_event AS DATE) >= '2025-09-01'
  ) AS _t
  WHERE
    _w = 1
), new_canceled_status AS (
  SELECT
    id_booking,
    id_user,
    status,
    reason,
    reason_enum,
    reason_category,
    type,
    ts_created,
    ts_first_event
  FROM (
    SELECT
      vsl.id_schedule AS id_booking,
      IF(NOT f.id_succeed_schedule IS NULL, f.id_succeed_user, vsl.id_author_user) AS id_user,
      'Cancelado' AS status,
      CASE
        WHEN NOT f.id_succeed_schedule IS NULL
        THEN 'SCHEDULE_CHANGE'
        WHEN vsl.reason = 'VISIT_OCCURRED_AT_A_DIFFERENT_TIME'
        THEN 'CANCELED_SCHEDULED_OTHER_TIME'
        WHEN vsl.reason = 'PROPERTY_ON_HOLD_FOR_ANOTHER_PROSPECT'
        THEN 'CANCELED_PROPERTY_SUSPENDED_ADVANCED_NEGOTIATIONS'
        WHEN vsl.reason = 'PERSON_SCHEDULED_FOR_ANOTHER_TIME'
        THEN 'CANCELED_SCHEDULED_OTHER_TIME'
        WHEN vsl.reason = 'PERSON_DOESNT_WANT_TO_WORK_ON_THIS_LOCATION'
        THEN 'CANCELED_AGENT_VISIT_TOO_FAR'
        WHEN vsl.reason = 'PERSON_IDENTIFIED_LISTING_AS_INACCURATE_OR_INCOMPLETE'
        THEN 'CANCELED_BY_OUT_OF_DATE_AD'
        WHEN vsl.reason = 'PROPERTY_RESERVED'
        THEN 'CANCELED_HOUSE_RESERVED'
        WHEN vsl.reason = 'REQUEST_EXPIRED'
        THEN 'OTHER'
        WHEN vsl.reason = 'PERSON_CANNOT_ATTEND' AND vsl.on_behalf_of = 'SUPPLY'
        THEN 'CANCELED_OWNER_CAN_NOT_ATTEND'
        WHEN vsl.reason = 'PERSON_CANNOT_ATTEND' AND vsl.on_behalf_of = 'DEMAND'
        THEN 'CANCELED_BY_TENANT_CAN_NOT_ATTEND'
        WHEN vsl.reason = 'PERSON_CANNOT_ATTEND' AND vsl.on_behalf_of = 'AGENT'
        THEN 'CANCELED_AGENT_CAN_NOT_ATTEND'
        WHEN vsl.reason = 'PERSON_CANNOT_ATTEND' AND vsl.on_behalf_of = 'TENANT_LIVING'
        THEN 'OTHER'
        WHEN vsl.reason = 'PERSON_DOESNT_WANT_5A' AND vsl.on_behalf_of = 'TENANT_LIVING'
        THEN 'OTHER'
        WHEN vsl.reason = 'PERSON_DOESNT_WANT_5A' AND vsl.on_behalf_of <> 'TENANT_LIVING'
        THEN 'CANCELED_CLIENT_GAVE_UP'
        WHEN vsl.reason = 'PERSON_NOT_INTERESTED_ON_THIS_PROPERTY_OR_ON_THIS_VISIT'
        AND vsl.on_behalf_of = 'AGENT'
        THEN 'CANCELED_AGENT_CAN_NOT_ATTEND'
        WHEN vsl.reason = 'PERSON_NOT_INTERESTED_ON_THIS_PROPERTY_OR_ON_THIS_VISIT'
        AND vsl.on_behalf_of <> 'AGENT'
        THEN 'CANCELED_BY_TENANT_NOT_INTERESTED'
        WHEN vsl.reason = 'PROPERTY_OR_PERSON_INDEFINITELY_UNAVAILABLE'
        AND vsl.on_behalf_of = 'DEMAND'
        THEN 'CANCELED_BY_TENANT_NOT_INTERESTED'
        WHEN vsl.reason = 'PROPERTY_OR_PERSON_INDEFINITELY_UNAVAILABLE'
        AND vsl.on_behalf_of = 'SUPPLY'
        THEN 'CANCELED_PROPERTY_UNAVAILABLE'
        WHEN vsl.reason = 'PROPERTY_TEMPORARILY_UNAVAILABLE' AND vsl.on_behalf_of = 'SUPPLY'
        THEN 'CANCELED_PROPERTY_UNAVAILABLE'
        WHEN vsl.reason = 'PROPERTY_TEMPORARILY_UNAVAILABLE' AND vsl.on_behalf_of = 'DEMAND'
        THEN 'OTHER'
        WHEN vsl.reason = 'QUINTO_ANDAR_CANNOT_CONTACT_ONE_OF_THE_PARTIES'
        AND vsl.on_behalf_of = 'SUPPLY'
        THEN 'CANCELED_OWNER_UNREACHABLE'
        WHEN vsl.reason = 'QUINTO_ANDAR_CANNOT_CONTACT_ONE_OF_THE_PARTIES'
        AND vsl.on_behalf_of = 'TENANT_LIVING'
        THEN 'OTHER'
        WHEN vsl.reason = 'QUINTO_ANDAR_CANNOT_CONTACT_ONE_OF_THE_PARTIES'
        AND vsl.on_behalf_of = 'DEMAND'
        THEN 'CANCELED_BY_TENANT_NOT_INTERESTED'
        WHEN vsl.reason = 'AGENT_TRANSFER_FAILED_TO_FIND_ANOTHER_AGENT'
        AND vsl.channel = 'AGENT_PWA'
        THEN 'CANCELED_AGENT_CAN_NOT_ATTEND'
        WHEN vsl.reason = 'AGENT_TRANSFER_FAILED_TO_FIND_ANOTHER_AGENT'
        AND vsl.channel <> 'AGENT_PWA'
        THEN 'OTHER'
        ELSE vsl.reason
      END AS reason,
      CASE
        WHEN NOT f.id_succeed_schedule IS NULL
        THEN 'SCHEDULE_CHANGE'
        WHEN vsl.reason = 'VISIT_OCCURRED_AT_A_DIFFERENT_TIME'
        THEN 'CANCELED_SCHEDULED_OTHER_TIME'
        WHEN vsl.reason = 'PROPERTY_ON_HOLD_FOR_ANOTHER_PROSPECT'
        THEN 'CANCELED_PROPERTY_SUSPENDED_ADVANCED_NEGOTIATIONS'
        WHEN vsl.reason = 'PERSON_SCHEDULED_FOR_ANOTHER_TIME'
        THEN 'CANCELED_SCHEDULED_OTHER_TIME'
        WHEN vsl.reason = 'PERSON_DOESNT_WANT_TO_WORK_ON_THIS_LOCATION'
        THEN 'CANCELED_AGENT_VISIT_TOO_FAR'
        WHEN vsl.reason = 'PERSON_IDENTIFIED_LISTING_AS_INACCURATE_OR_INCOMPLETE'
        THEN 'CANCELED_BY_OUT_OF_DATE_AD'
        WHEN vsl.reason = 'PROPERTY_RESERVED'
        THEN 'CANCELED_HOUSE_RESERVED'
        WHEN vsl.reason = 'REQUEST_EXPIRED'
        THEN 'OTHER'
        WHEN vsl.reason = 'PERSON_CANNOT_ATTEND' AND vsl.on_behalf_of = 'SUPPLY'
        THEN 'CANCELED_OWNER_CAN_NOT_ATTEND'
        WHEN vsl.reason = 'PERSON_CANNOT_ATTEND' AND vsl.on_behalf_of = 'DEMAND'
        THEN 'CANCELED_BY_TENANT_CAN_NOT_ATTEND'
        WHEN vsl.reason = 'PERSON_CANNOT_ATTEND' AND vsl.on_behalf_of = 'AGENT'
        THEN 'CANCELED_AGENT_CAN_NOT_ATTEND'
        WHEN vsl.reason = 'PERSON_CANNOT_ATTEND' AND vsl.on_behalf_of = 'TENANT_LIVING'
        THEN 'OTHER'
        WHEN vsl.reason = 'PERSON_DOESNT_WANT_5A' AND vsl.on_behalf_of = 'TENANT_LIVING'
        THEN 'OTHER'
        WHEN vsl.reason = 'PERSON_DOESNT_WANT_5A' AND vsl.on_behalf_of <> 'TENANT_LIVING'
        THEN 'CANCELED_CLIENT_GAVE_UP'
        WHEN vsl.reason = 'PERSON_NOT_INTERESTED_ON_THIS_PROPERTY_OR_ON_THIS_VISIT'
        AND vsl.on_behalf_of = 'AGENT'
        THEN 'CANCELED_AGENT_CAN_NOT_ATTEND'
        WHEN vsl.reason = 'PERSON_NOT_INTERESTED_ON_THIS_PROPERTY_OR_ON_THIS_VISIT'
        AND vsl.on_behalf_of <> 'AGENT'
        THEN 'CANCELED_BY_TENANT_NOT_INTERESTED'
        WHEN vsl.reason = 'PROPERTY_OR_PERSON_INDEFINITELY_UNAVAILABLE'
        AND vsl.on_behalf_of = 'DEMAND'
        THEN 'CANCELED_BY_TENANT_NOT_INTERESTED'
        WHEN vsl.reason = 'PROPERTY_OR_PERSON_INDEFINITELY_UNAVAILABLE'
        AND vsl.on_behalf_of = 'SUPPLY'
        THEN 'CANCELED_PROPERTY_UNAVAILABLE'
        WHEN vsl.reason = 'PROPERTY_TEMPORARILY_UNAVAILABLE' AND vsl.on_behalf_of = 'SUPPLY'
        THEN 'CANCELED_PROPERTY_UNAVAILABLE'
        WHEN vsl.reason = 'PROPERTY_TEMPORARILY_UNAVAILABLE' AND vsl.on_behalf_of = 'DEMAND'
        THEN 'OTHER'
        WHEN vsl.reason = 'QUINTO_ANDAR_CANNOT_CONTACT_ONE_OF_THE_PARTIES'
        AND vsl.on_behalf_of = 'SUPPLY'
        THEN 'CANCELED_OWNER_UNREACHABLE'
        WHEN vsl.reason = 'QUINTO_ANDAR_CANNOT_CONTACT_ONE_OF_THE_PARTIES'
        AND vsl.on_behalf_of = 'TENANT_LIVING'
        THEN 'OTHER'
        WHEN vsl.reason = 'QUINTO_ANDAR_CANNOT_CONTACT_ONE_OF_THE_PARTIES'
        AND vsl.on_behalf_of = 'DEMAND'
        THEN 'CANCELED_BY_TENANT_NOT_INTERESTED'
        WHEN vsl.reason = 'AGENT_TRANSFER_FAILED_TO_FIND_ANOTHER_AGENT'
        AND vsl.channel = 'AGENT_PWA'
        THEN 'CANCELED_AGENT_CAN_NOT_ATTEND'
        WHEN vsl.reason = 'AGENT_TRANSFER_FAILED_TO_FIND_ANOTHER_AGENT'
        AND vsl.channel <> 'AGENT_PWA'
        THEN 'OTHER'
        ELSE vsl.reason
      END AS reason_enum,
      CASE
        WHEN vsl.on_behalf_of = 'DEMAND'
        THEN 'Tenant'
        WHEN vsl.on_behalf_of = 'SUPPLY'
        THEN 'Owner'
        WHEN vsl.on_behalf_of = 'AGENT'
        THEN 'Agent'
        ELSE 'Other'
      END AS reason_category,
      'Visita' AS type,
      ts_created,
      f.ts_first_event,
      ROW_NUMBER() OVER (PARTITION BY f.id_schedule ORDER BY id_visit_status_log DESC) AS _w,
      f.id_schedule,
      id_visit_status_log
    FROM new_filtered_schedule AS f
    LEFT JOIN datalake_ebdb_clean.visit_status_log AS vsl
      ON f.id_schedule = vsl.id_schedule
    WHERE
      (
        vsl.event_type IN ('VISIT_CANCELED', 'VISIT_REQUEST_CANCELED')
        OR NOT f.id_succeed_schedule IS NULL
      )
      AND CAST(f.ts_first_event AS DATE) >= '2025-09-01'
  ) AS _t
  WHERE
    _w = 1
), all_events AS (
  SELECT
    id_booking,
    id_user,
    status,
    reason,
    reason_enum,
    reason_category,
    'OLD' AS source,
    type,
    ts_created,
    ts_first_event
  FROM old_status
  UNION ALL
  SELECT
    id_booking,
    id_user,
    status,
    reason,
    reason_enum,
    reason_category,
    'NEW' AS source,
    type,
    ts_created,
    ts_first_event
  FROM new_requested_status
  UNION ALL
  SELECT
    id_booking,
    id_user,
    status,
    reason,
    reason_enum,
    reason_category,
    'NEW' AS source,
    type,
    ts_created,
    ts_first_event
  FROM new_confirmed_status
  UNION ALL
  SELECT
    id_booking,
    id_user,
    status,
    reason,
    reason_enum,
    reason_category,
    'NEW' AS source,
    type,
    ts_created,
    ts_first_event
  FROM new_canceled_status
)
SELECT
  id_booking_status,
  id_booking,
  id_user,
  status,
  reason,
  reason_enum,
  reason_category,
  source,
  type,
  ts_created,
  ts_first_event
FROM (
  SELECT
    CONCAT(CAST(id_booking AS STRING), '-', status) AS id_booking_status,
    id_booking,
    id_user,
    status,
    reason,
    reason_enum,
    reason_category,
    source,
    type,
    ts_created,
    ts_first_event,
    ROW_NUMBER() OVER (PARTITION BY id_booking, status ORDER BY IF(source = 'OLD', 1, 0) DESC) AS _w
  FROM all_events
) AS _t
WHERE
  _w = 1
