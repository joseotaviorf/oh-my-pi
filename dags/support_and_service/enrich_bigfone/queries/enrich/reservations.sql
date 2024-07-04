WITH reservation_events AS (
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
    ts_created
  FROM
    datalake_bigfone_clean.event
  WHERE
    event_type LIKE 'reservation.%'
    AND year >= 2023
),
reservation_queue AS (
  SELECT
    id_reservation,
    id_queue,
    queue_name
  FROM
    reservation_events
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_reservation ORDER BY ts_created) = 1
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
    COUNT(
      CASE
        WHEN event_type = 'reservation.accepted' OR event_type = 'reservation.completed' THEN id_reservation
      END
    ) > 0 AS is_answered,
    COUNT(
      CASE
        WHEN event_type = 'reservation.timeout' THEN id_reservation
      END
    ) > 0 AS is_timeout,
    COUNT(
      CASE
        WHEN event_type = 'reservation.rejected' THEN id_reservation
      END
    ) > 0 AS is_rejected,
    COUNT(
      CASE
        WHEN event_type = 'reservation.canceled' THEN id_reservation
      END
    ) > 0 AS is_canceled,
    MIN(ts_created) AS ts_created,
    MAX(ts_created) AS ts_ended
  FROM
    reservation_events
  GROUP BY ALL
)
SELECT
  r.id_call,
  r.id_task,
  r.id_reservation,
  rq.id_queue,
  r.id_worker,
  r.direction,
  r.channel_type,
  r.bpo_name,
  rq.queue_name,
  r.worker_email,
  r.from_phone_number,
  r.to_phone_number,
  r.is_answered,
  r.is_timeout,
  r.is_rejected,
  r.is_canceled,
  r.ts_created,
  r.ts_ended
FROM
  reservations AS r
LEFT JOIN
  reservation_queue AS rq
    ON rq.id_reservation = r.id_reservation
