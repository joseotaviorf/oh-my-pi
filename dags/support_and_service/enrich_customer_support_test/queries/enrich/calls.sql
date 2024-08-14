WITH call_sessions AS (
  SELECT
    id AS id_session,
    user_data:["user_id"] AS id_user,
    source_identity
  FROM
    datalake_sauron_clean.session
  WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY source_identity ORDER BY ts_updated DESC) = 1
),
call_events AS (
  SELECT
    id_task,
    id_call,
    id_reservation,
    id_queue,
    id_worker,
    event_type,
    direction,
    channel_type,
    bpo_name,
    queue_name,
    worker_email,
    from_phone_number,
    CASE
      WHEN direction = 'outbound' THEN outbound_to_phone_number
      ELSE to_phone_number
    END AS to_phone_number,
    ts_created,
    MIN(ts_created) OVER(PARTITION BY id_task ORDER BY ts_created) AS ts_task_created,
    MAX(ts_created) OVER(PARTITION BY id_reservation ORDER BY ts_created) AS ts_reservation_ended
  FROM
    datalake_bigfone_clean.event
  WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
),
reservation_queue AS (
  SELECT
    id_reservation,
    id_queue,
    queue_name
  FROM
    call_events
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_reservation ORDER BY ts_task_created) = 1
),
reservations AS (
  SELECT
    id_task,
    MAX(id_call) id_call,
    id_reservation,
    id_worker,
    direction,
    channel_type,
    MAX(bpo_name) AS bpo_name,
    worker_email,
    from_phone_number,
    to_phone_number,
    TRUE AS is_call_answered,
    COUNT(
      CASE
        WHEN event_type = 'reservation.accepted' OR event_type = 'reservation.completed' THEN id_reservation
      END
    ) > 0 AS is_reservation_answered,
    COUNT(
      CASE
        WHEN event_type = 'reservation.timeout' THEN id_reservation
      END
    ) > 0 AS is_reservation_timeout,
    COUNT(
      CASE
        WHEN event_type = 'reservation.rejected' THEN id_reservation
      END
    ) > 0 AS is_reservation_rejected,
    COUNT(
      CASE
        WHEN event_type = 'reservation.canceled' THEN id_reservation
      END
    ) > 0 AS is_reservation_canceled,
    MIN(
      CASE
        WHEN event_type = 'reservation.created' THEN ts_created
      END
    ) AS ts_reservation_created,
    MIN(
      CASE
        WHEN event_type = 'reservation.accepted' THEN ts_created
      END
    ) AS ts_reservation_accepted,
    MAX(ts_reservation_ended) AS ts_reservation_ended,
    MIN(ts_task_created) AS ts_task_created
  FROM
    call_events
  WHERE
    event_type LIKE 'reservation.%'
  GROUP BY ALL
),
unanswered_calls AS (
  SELECT
    id_task,
    MAX(id_call) id_call,
    NULL AS id_reservation,
    NULL AS id_worker,
    direction,
    channel_type,
    MAX(bpo_name) AS bpo_name,
    NULL AS worker_email,
    from_phone_number,
    to_phone_number,
    FALSE AS is_call_answered,
    NULL AS is_reservation_answered,
    NULL AS is_reservation_timeout,
    NULL AS is_reservation_rejected,
    NULL AS is_reservation_canceled,
    NULL AS ts_reservation_created,
    NULL AS ts_reservation_accepted,
    NULL AS ts_reservation_ended,
    MIN(ts_task_created) AS ts_task_created
  FROM
    call_events
  WHERE
    direction IS NOT NULL
  GROUP BY ALL
  HAVING COUNT(DISTINCT(id_reservation)) < 1
),
calls AS (
  SELECT
    id_call,
    id_task,
    id_reservation,
    id_worker,
    direction,
    channel_type,
    bpo_name,
    worker_email,
    from_phone_number,
    to_phone_number,
    is_call_answered,
    is_reservation_answered,
    is_reservation_timeout,
    is_reservation_rejected,
    is_reservation_canceled,
    ts_reservation_created,
    ts_reservation_accepted,
    ts_reservation_ended,
    ts_task_created
  FROM
    reservations
  UNION ALL
  SELECT
    id_call,
    id_task,
    id_reservation,
    id_worker,
    direction,
    channel_type,
    bpo_name,
    worker_email,
    from_phone_number,
    to_phone_number,
    is_call_answered,
    is_reservation_answered,
    is_reservation_timeout,
    is_reservation_rejected,
    is_reservation_canceled,
    ts_reservation_created,
    ts_reservation_accepted,
    ts_reservation_ended,
    ts_task_created
  FROM
    unanswered_calls
)
SELECT
  c.id_call,
  cs.id_session,
  cs.id_user,
  c.id_task,
  c.id_reservation,
  rq.id_queue,
  c.id_worker,
  c.direction,
  c.channel_type,
  c.bpo_name,
  rq.queue_name,
  c.worker_email,
  c.from_phone_number,
  c.to_phone_number,
  c.is_call_answered,
  c.is_reservation_answered,
  c.is_reservation_timeout,
  c.is_reservation_rejected,
  c.is_reservation_canceled,
  c.ts_task_created,
  c.ts_reservation_created,
  c.ts_reservation_accepted,
  c.ts_reservation_ended
FROM
  calls AS c
LEFT JOIN
  reservation_queue AS rq
    ON rq.id_reservation = c.id_reservation
LEFT JOIN
  call_sessions AS cs
    ON cs.source_identity = c.id_call
    OR cs.source_identity = c.id_task
