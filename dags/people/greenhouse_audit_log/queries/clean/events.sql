WITH source AS (
  SELECT *
  FROM datalake_greenhouse_audit_log_raw.events
  WHERE
    MAKE_DATE(year, month, day) >= DATE('{load_start_date}')
    AND MAKE_DATE(year, month, day) < DATE('{load_end_date}')
)
SELECT
  -- ids
  COALESCE(
    get_json_object(raw_payload, '$.organization_id'),
    CAST(organization_id AS STRING)
  ) AS id_organization,
  COALESCE(
    get_json_object(raw_payload, '$.request.id'),
    CAST(request.id AS STRING)
  ) AS id_request,
  COALESCE(
    get_json_object(raw_payload, '$.performer.id'),
    CAST(performer.id AS STRING)
  ) AS id_performer,
  COALESCE(
    get_json_object(raw_payload, '$.event.target_id'),
    CAST(event.target_id AS STRING)
  ) AS id_event_target,
  COALESCE(
    FROM_JSON(
      get_json_object(raw_payload, '$.event.meta.close_reason_id'),
      'array<string>'
    )[0],
    FROM_JSON(
      get_json_object(TO_JSON(event.meta), '$.close_reason_id'),
      'array<string>'
    )[0]
  ) AS id_close_reason_before_event,
  COALESCE(
    FROM_JSON(
      get_json_object(raw_payload, '$.event.meta.close_reason_id'),
      'array<string>'
    )[1],
    FROM_JSON(
      get_json_object(TO_JSON(event.meta), '$.close_reason_id'),
      'array<string>'
    )[1]
  ) AS id_close_reason_after_event,
  -- non-metrics
  COALESCE(
    get_json_object(raw_payload, '$.request.type'),
    request.type
  ) AS request_type,
  COALESCE(
    get_json_object(raw_payload, '$.performer.type'),
    performer.type
  ) AS performer_type,
  COALESCE(
    get_json_object(raw_payload, '$.performer.ip_address'),
    performer.ip_address
  ) AS performer_ip_address,
  COALESCE(
    get_json_object(raw_payload, '$.performer.meta.name'),
    get_json_object(performer.meta, '$.name')
  ) AS performer_name,
  COALESCE(
    get_json_object(raw_payload, '$.performer.meta.username'),
    get_json_object(performer.meta, '$.username')
  ) AS performer_username,
  COALESCE(
    get_json_object(raw_payload, '$.event.type'),
    event.type
  ) AS event_type,
  COALESCE(
    get_json_object(raw_payload, '$.event.target_type'),
    event.target_type
  ) AS event_target_type,
  -- event.meta as JSON string (schema varies by event type)
  COALESCE(
    get_json_object(raw_payload, '$.event.meta'),
    TO_JSON(event.meta)
  ) AS event_meta,
  -- dates
  CAST(
    COALESCE(
      FROM_JSON(
        get_json_object(raw_payload, '$.event.meta.close_date'),
        'array<string>'
      )[0],
      FROM_JSON(
        get_json_object(TO_JSON(event.meta), '$.close_date'),
        'array<string>'
      )[0]
    )
    AS DATE
  ) AS dt_closed_before_event,
  CAST(
    COALESCE(
      FROM_JSON(
        get_json_object(raw_payload, '$.event.meta.close_date'),
        'array<string>'
      )[1],
      FROM_JSON(
        get_json_object(TO_JSON(event.meta), '$.close_date'),
        'array<string>'
      )[1]
    )
    AS DATE
  ) AS dt_closed_after_event,
  -- timestamp
  CAST(
    COALESCE(
      get_json_object(raw_payload, '$.event_time'),
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
  source
