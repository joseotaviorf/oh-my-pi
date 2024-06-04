SELECT
  id_task,
  id_call,
  id_reservation,
  id_queue,
  id_worker,
  twilio_sid,
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
  CASE
    WHEN event_type = 'reservation.accepted' OR event_type = 'reservation.completed' THEN TRUE
    ELSE FALSE
  END AS is_answered,
  CASE
    WHEN event_type = 'reservation.timeout' THEN TRUE
    ELSE FALSE
  END AS is_timeout,
  CASE
    WHEN event_type = 'reservation.rejected' THEN TRUE
    ELSE FALSE
  END AS is_rejected,
  CASE
    WHEN event_type = 'reservation.canceled' THEN TRUE
    ELSE FALSE
  END AS is_canceled,
  ts_created
FROM
  datalake_bigfone_clean.event
WHERE
  event_type LIKE 'reservation.%'
  AND year >= 2023
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY id_reservation ORDER BY ts_created DESC) = 1
