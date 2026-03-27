SELECT
  -- ids
  COALESCE(
    GET_JSON_OBJECT(raw_payload, '$.organization_id'),
    CAST(organization_id AS STRING)
  ) AS id_organization,
  COALESCE(
    GET_JSON_OBJECT(raw_payload, '$.request.id'),
    CAST(request.id AS STRING)
  ) AS id_request,
  COALESCE(
    GET_JSON_OBJECT(raw_payload, '$.performer.id'),
    CAST(performer.id AS STRING)
  ) AS id_performer,
  CAST(GET_JSON_OBJECT(raw_payload, '$.event.target_id') AS STRING) AS id_event_target,
  FROM_JSON(
    GET_JSON_OBJECT(raw_payload, '$.event.meta.close_reason_id'),
    'array<string>'
  )[0] AS id_close_reason_before_event,
  FROM_JSON(
    GET_JSON_OBJECT(raw_payload, '$.event.meta.close_reason_id'),
    'array<string>'
  )[1] AS id_close_reason_after_event,
  -- non-metrics
  COALESCE(
    GET_JSON_OBJECT(raw_payload, '$.request.type'),
    request.type
  ) AS request_type,
  COALESCE(
    GET_JSON_OBJECT(raw_payload, '$.performer.type'),
    performer.type
  ) AS performer_type,
  COALESCE(
    GET_JSON_OBJECT(raw_payload, '$.performer.ip_address'),
    performer.ip_address
  ) AS performer_ip_address,
  GET_JSON_OBJECT(raw_payload, '$.performer.meta.name') AS performer_name,
  GET_JSON_OBJECT(raw_payload, '$.performer.meta.username') AS performer_username,
  COALESCE(
    GET_JSON_OBJECT(raw_payload, '$.event.type'),
    event.type
  ) AS event_type,
  COALESCE(
    GET_JSON_OBJECT(raw_payload, '$.event.target_type'),
    event.target_type
  ) AS event_target_type,
  GET_JSON_OBJECT(raw_payload, '$.event.meta') AS event_meta,
  -- dates
  CAST(
    FROM_JSON(
      GET_JSON_OBJECT(raw_payload, '$.event.meta.close_date'),
      'array<string>'
    )[0] AS DATE
  ) AS dt_closed_before_event,
  CAST(
    FROM_JSON(
      GET_JSON_OBJECT(raw_payload, '$.event.meta.close_date'),
      'array<string>'
    )[1] AS DATE
  ) AS dt_closed_after_event,
  -- timestamp
  CAST(
    COALESCE(
      GET_JSON_OBJECT(raw_payload, '$.event_time'),
      event_time
    )
    AS TIMESTAMP
  ) AS ts_event,
  NOW() AS ts_load,
  -- partitions
  year,
  month,
  day
FROM
  datalake_greenhouse_audit_log_raw.events
WHERE
  MAKE_DATE(year, month, day) >= DATE('{load_start_date}')
  AND MAKE_DATE(year, month, day) < DATE('{load_end_date}')