WITH sss_and_sauron_call_sessions AS (
  SELECT 
    id AS id_session,
    get_json_object(user_data, '$.user_id') AS id_user,
    public_id AS id_sss_session,
    source_identity
  FROM 
    datalake_sauron_clean.session
  WHERE 
    source in ('call_in_app', 'call')
    AND MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" - INTERVAL 30 DAY AND "{load_end_date}"
  UNION 
  SELECT 
    id AS id_session,
    get_json_object(user_data, '$.user_id') AS id_user,
    public_id AS id_sss_session,
    source_identity
  FROM 
    datalake_support_session_service_clean.support_session
  WHERE 
    source in ('call_in_app', 'call')
    AND MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" - INTERVAL 30 DAY AND "{load_end_date}"
    AND ts_created >= DATE('2025-11-10')
),
call_sessions_ranked AS (
  SELECT
    source_identity,
    id_session,
    id_user,
    id_sss_session,
    ROW_NUMBER() OVER (PARTITION BY source_identity ORDER BY id_session) AS rn
  FROM
    sss_and_sauron_call_sessions
),
call_sessions AS (
  SELECT
    source_identity,
    id_session,
    id_user,
    id_sss_session
  FROM
    call_sessions_ranked
  WHERE
    rn = 1
),
call_events AS (
  SELECT
    id_task,
    MAX(id_call) OVER(PARTITION BY id_task) AS id_call,
    id_reservation,
    id_queue,
    id_worker,
    event_type,
    LOWER(direction) AS direction,
    channel_type,
    bpo_name,
    queue_name,
    worker_email,
    from_phone_number,
    task_cancelation_reason,
    CASE
      WHEN LOWER(direction) = 'outbound' THEN outbound_to_phone_number
      ELSE to_phone_number
    END AS to_phone_number,
    MAX(waiting_time_sec) OVER(PARTITION BY id_reservation) AS waiting_time_sec,
    ts_created,
    MIN(ts_created) OVER(PARTITION BY id_task ORDER BY ts_created) AS ts_task_created,
    MAX(ts_created) OVER(PARTITION BY id_reservation ORDER BY ts_created) AS ts_reservation_ended
  FROM
    datalake_bigfone_clean.event
  WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" - INTERVAL 30 DAY  AND "{load_end_date}"
),
reservation_queues_ranked AS (
  SELECT
    id_task,
    id_reservation,
    id_queue,
    queue_name,
    ROW_NUMBER() OVER(PARTITION BY id_reservation ORDER BY ts_task_created) AS rn
  FROM
    call_events
),
reservation_queues AS (
  SELECT DISTINCT
    id_task,
    id_reservation,
    id_queue,
    queue_name
  FROM
    reservation_queues_ranked
  WHERE
    rn = 1
),
queues_per_reservation AS (
  SELECT
    id_task,
    id_reservation,
    COUNT(DISTINCT(queue_name)) AS total_queues
  FROM
    call_events
  WHERE
    id_reservation is not null
  GROUP BY 1, 2
),
task_queues_ranked AS (
  SELECT
    id_task,
    id_queue,
    queue_name,
    ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_task_created) AS rn
  FROM
    call_events
),
task_queues AS (
  SELECT
    id_task,
    id_queue,
    queue_name
  FROM
    task_queues_ranked
  WHERE
    rn = 1
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
    waiting_time_sec,
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
  GROUP BY
    id_task,
    id_reservation,
    id_worker,
    direction,
    channel_type,
    worker_email,
    from_phone_number,
    to_phone_number,
    waiting_time_sec
),
call_answered_flag AS (
  SELECT
    id_task,
    MAX(is_reservation_answered) AS is_call_answered
  FROM
    reservations
  GROUP BY 1
),
unanswered_calls AS (
  SELECT
    ce.id_task,
    MAX(ce.id_call) id_call,
    NULL AS id_reservation,
    NULL AS id_worker,
    ce.direction,
    ce.channel_type,
    MAX(ce.bpo_name) AS bpo_name,
    NULL AS worker_email,
    ce.from_phone_number,
    ce.to_phone_number,
    NULL AS waiting_time_sec,
    FALSE AS is_call_answered,
    FALSE AS is_reservation_answered,
    FALSE AS is_reservation_timeout,
    FALSE AS is_reservation_rejected,
    FALSE AS is_reservation_canceled,
    NULL AS ts_reservation_created,
    NULL AS ts_reservation_accepted,
    NULL AS ts_reservation_ended,
    MIN(ce.ts_task_created) AS ts_task_created
  FROM
    call_events AS ce
  LEFT JOIN
    reservations AS r
      ON r.id_task = ce.id_task
  WHERE
    ce.direction IS NOT NULL
    AND ce.task_cancelation_reason IS NOT NULL
    AND r.id_task IS NULL
  GROUP BY
    ce.id_task,
    ce.direction,
    ce.channel_type,
    ce.from_phone_number,
    ce.to_phone_number
  HAVING COUNT(DISTINCT(ce.id_reservation)) < 1
),
reservation_metrics AS (
  SELECT
    r.id_call,
    r.id_task,
    r.id_reservation,
    qpr.total_queues,
    r.id_worker,
    r.direction,
    r.channel_type,
    r.bpo_name,
    r.worker_email,
    r.from_phone_number,
    r.to_phone_number,
    r.waiting_time_sec,
    r.is_reservation_answered,
    COALESCE(
      CAST(
        SUM(CAST(is_reservation_answered AS INTEGER)) OVER(
          PARTITION BY r.id_task ORDER BY r.ts_reservation_created ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
        )
        AS BOOLEAN
      ), FALSE
    ) AS has_following_answered_reservation,
    r.is_reservation_timeout,
    r.is_reservation_rejected,
    r.is_reservation_canceled,
    r.ts_reservation_created,
    r.ts_reservation_accepted,
    r.ts_reservation_ended,
    r.ts_task_created
  FROM
    reservations AS r
  LEFT JOIN
    queues_per_reservation AS qpr
      ON qpr.id_reservation = r.id_reservation
  LEFT JOIN
    call_answered_flag AS caf
      ON caf.id_task = r.id_task
),
calls AS (
  SELECT
    r.id_call,
    r.id_task,
    r.id_reservation,
    r.id_worker,
    r.direction,
    r.channel_type,
    r.bpo_name,
    r.worker_email,
    r.from_phone_number,
    r.to_phone_number,
    r.waiting_time_sec,
    caf.is_call_answered,
    CAST(
      SUM(
        CAST(
          CASE
            WHEN r.has_following_answered_reservation IS FALSE
              AND r.total_queues > 1 THEN TRUE
            ELSE FALSE
          END AS INTEGER
        )
      ) OVER(PARTITION BY r.id_task ORDER BY r.ts_reservation_created ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
      AS BOOLEAN
    ) AS ends_in_abandon,
    r.is_reservation_answered,
    r.is_reservation_timeout,
    r.is_reservation_rejected,
    r.is_reservation_canceled,
    r.ts_reservation_created,
    r.ts_reservation_accepted,
    r.ts_reservation_ended,
    r.ts_task_created
  FROM
    reservation_metrics AS r
  LEFT JOIN
    call_answered_flag AS caf
      ON caf.id_task = r.id_task
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
    waiting_time_sec,
    is_call_answered,
    NULL AS ends_in_abandon,
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
),
call_session_matches AS (
  SELECT
    CONCAT_WS(
      '|',
      COALESCE(CAST(c.id_call AS STRING), ''),
      COALESCE(CAST(c.id_task AS STRING), '')
    ) AS call_match_key,
    cs.id_session,
    cs.id_sss_session,
    cs.id_user
  FROM
    calls AS c
  INNER JOIN
    call_sessions AS cs
      ON cs.source_identity = c.id_call
  UNION
  SELECT
    CONCAT_WS(
      '|',
      COALESCE(CAST(c.id_call AS STRING), ''),
      COALESCE(CAST(c.id_task AS STRING), '')
    ) AS call_match_key,
    cs.id_session,
    cs.id_sss_session,
    cs.id_user
  FROM
    calls AS c
  INNER JOIN
    call_sessions AS cs
      ON cs.source_identity = c.id_task
)
SELECT DISTINCT
  c.id_call,
  cs.id_session,
  cs.id_sss_session,
  cs.id_user,
  c.id_task,
  c.id_reservation,
  COALESCE(rq.id_queue, tq.id_queue) AS id_queue,
  c.id_worker,
  CASE
    WHEN c.channel_type = 'call-in-app' OR c.direction = 'outbound-api' THEN 'in app'
    ELSE c.direction
  END AS origin,
  c.direction,
  c.channel_type,
  c.bpo_name,
  COALESCE(rq.queue_name, tq.queue_name) AS queue_name,
  c.worker_email,
  c.from_phone_number,
  c.to_phone_number,
  c.waiting_time_sec,
  c.is_call_answered,
  c.ends_in_abandon,
  c.is_reservation_answered,
  c.is_reservation_timeout,
  c.is_reservation_rejected,
  c.is_reservation_canceled,
  c.ts_task_created,
  c.ts_reservation_created,
  c.ts_reservation_accepted,
  c.ts_reservation_ended,
  YEAR(ts_task_created) AS year,
  MONTH(ts_task_created) AS month,
  DAY(ts_task_created) AS day
FROM
  calls AS c
LEFT JOIN
  reservation_queues AS rq
    ON rq.id_reservation = c.id_reservation
LEFT JOIN
  task_queues AS tq
    ON tq.id_task = c.id_task
    AND c.id_reservation IS NULL
LEFT JOIN
  call_session_matches AS cs
    ON cs.call_match_key = CONCAT_WS(
      '|',
      COALESCE(CAST(c.id_call AS STRING), ''),
      COALESCE(CAST(c.id_task AS STRING), '')
    )
    
