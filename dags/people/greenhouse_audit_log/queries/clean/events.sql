SELECT
  -- ids
  organization_id AS id_organization,
  request.id AS id_request,
  performer.id AS id_performer,
  event.target_id AS id_event_target,
  -- non-metrics
  request.type AS request_type,
  performer.type AS performer_type,
  performer.ip_address AS performer_ip_address,
  get_json_object(performer.meta, '$.name') AS performer_name,
  get_json_object(performer.meta, '$.username') AS performer_username,
  event.type AS event_type,
  event.target_type AS event_target_type,
  -- event.meta as JSON string (schema varies by event type)
  CAST(event.meta AS STRING) AS event_meta,
  -- timestamp
  CAST(event_time AS TIMESTAMP) AS ts_event,
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

