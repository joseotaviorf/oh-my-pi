WITH time_metrics AS (
  SELECT
    id_segment AS id_task,
    id_reservation,
    total_queue_time,
    total_talk_time,
    total_wrap_up_time,
    total_handling_time,
    total_waiting_time,
    first_reply_time,
    dt_created
  FROM
    datalake_twilio_flex_insights_clean.conversation_time_metrics
  QUALIFY -- TODO: this is probably avoidable if dt_created is filtered
    ROW_NUMBER() OVER(PARTITION BY id_segment ORDER BY dt_created DESC) = 1
),
-- TODO: This CTE could be filtered by date/partition
average_reply_time AS (
  SELECT
    id_task,
    msg_sender AS agent_email,
    AVG(reply_time) AS average_reply_time
  FROM
    datalake_quinto_messenger.message
  WHERE
    msg_sender LIKE "%@%.com%"
  GROUP BY 1, 2
),
demand AS (
  SELECT DISTINCT
    id_session,
    id_call,
    id_task,
    id_reservation,
    id_user,
    queue_name,
    direction,
    'call' AS channel,
    origin,
    CASE
      WHEN id_reservation IS NULL THEN 'abandoned'
      WHEN ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_task_created DESC) = 1 THEN 'completed'
      ELSE 'transferred'
    END AS status,
    worker_email,
    CASE
      WHEN direction = 'inbound' THEN to_phone_number
      WHEN direction = 'outbound' THEN from_phone_number
    END AS quinto_andar_phone_number,
    CASE
      WHEN direction = 'inbound' THEN from_phone_number
      WHEN direction = 'outbound' THEN to_phone_number
    END AS customer_phone_number,
    NULL AS customer_email,
    waiting_time_sec,
    NULL AS seconds_to_first_response,
    NULL AS is_per_team_task,
    is_call_answered AS is_contact_answered,
    is_reservation_answered AS is_interaction_answered,
    ts_task_created,
    ts_reservation_created,
    ts_reservation_ended,
    year,
    month,
    day
  FROM
    datalake_customer_support.calls
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
  UNION ALL
  SELECT DISTINCT
    id_session,
    NULL AS id_call,
    id_task,
    NULL AS id_reservation,
    id_user,
    queue_name,
    'inbound' AS direction,
    'chat' AS channel,
    origin,
    CASE
      WHEN task_completion_reason = 'task idled' THEN 'idled'
      WHEN task_completion_reason = 'session expired' THEN 'expired'
      WHEN task_completion_reason = 'task completed' THEN 'completed'
      WHEN task_completion_reason = 'task transferred' THEN 'transferred'
      WHEN ROW_NUMBER() OVER(PARTITION BY id_session ORDER BY ts_created DESC) = 1 THEN 'completed'
      ELSE 'transferred'
    END AS status,
    worker_email,
    twilio_phone_number AS quinto_andar_phone_number,
    customer_phone_number,
    customer_email,
    NULL AS waiting_time_sec,
    seconds_to_first_response,
    is_per_team_task,
    TRUE AS is_contact_answered,
    CASE
      WHEN task_status = 'canceled' THEN FALSE
      WHEN task_completion_reason = 'Task TTL Exceeded or Max assignment count exceeded' THEN FALSE
      ELSE TRUE
    END AS is_interaction_answered,
    ts_created AS ts_task_created,
    NULL AS ts_reservation_created,
    NULL AS ts_reservation_ended,
    year,
    month,
    day
  FROM
    datalake_customer_support.chats
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
),
contacts AS (
  SELECT
    CASE
      WHEN d.channel = 'call' THEN MD5(COALESCE(d.id_call, d.id_task))
      WHEN d.channel = 'chat' THEN MD5(d.id_session)
    END AS sk_contact,
    CASE
      WHEN d.channel = 'call' THEN MD5(COALESCE(d.id_reservation, CONCAT(COALESCE(d.id_call, d.id_task), 'n/a')))
      WHEN d.channel = 'chat' THEN MD5(d.id_task)
    END AS sk_interaction,
    MD5(d.queue_name) AS sk_department,
    d.id_session AS sk_session,
    d.id_task AS sk_task,
    CAST(COALESCE(t1.id_ticket, t2.id_ticket) AS BIGINT) AS sk_ticket,
    CAST(d.id_user AS BIGINT) AS sk_user,
    d.queue_name,
    d.channel,
    d.direction,
    d.origin,
    d.status,
    d.worker_email,
    d.quinto_andar_phone_number,
    d.customer_phone_number,
    d.customer_email,
    art.average_reply_time,
    tm.total_talk_time,
    tm.total_queue_time,
    tm.total_wrap_up_time,
    tm.total_waiting_time,
    CASE
      WHEN d.channel = 'chat' THEN d.seconds_to_first_response
      WHEN d.channel = 'call' THEN d.waiting_time_sec
    END AS first_reply_time,
    tm.total_handling_time,
    d.is_per_team_task,
    d.is_contact_answered,
    d.is_interaction_answered,
    d.ts_task_created,
    d.ts_reservation_created,
    d.ts_reservation_ended,
    NOW() AS ts_load
  FROM
    demand AS d
  LEFT JOIN
    time_metrics AS tm
      ON tm.id_task = d.id_task
      OR tm.id_reservation = d.id_reservation
  LEFT JOIN
    average_reply_time AS art
      ON art.id_task = d.id_task
      AND art.agent_email = d.worker_email
      AND d.channel = 'chat'
  LEFT JOIN
      datalake_customer_support.tickets AS t1
        ON t1.id_twilio = d.id_call
        AND STARTSWITH(t1.id_twilio, "CA")
        AND d.channel = 'call'
    LEFT JOIN
      datalake_customer_support.tickets AS t2
        ON t2.id_twilio = d.id_task
        AND STARTSWITH(t2.id_twilio, "WT")
        AND d.channel = 'call'
    LEFT JOIN
      datalake_customer_support.tickets AS t3
        ON t3.id_session = d.id_session
        AND d.channel = 'chat'
)
SELECT
  sk_contact,
  sk_interaction,
  sk_session,
  sk_task,
  COALESCE(sk_ticket, -1) AS sk_ticket,
  COALESCE(sk_user, -1) AS sk_user,
  LAG(sk_department) OVER(PARTITION BY sk_contact ORDER BY ts_task_created) AS sk_prev_department,
  sk_department,
  LEAD(sk_department) OVER(PARTITION BY sk_contact ORDER BY ts_task_created) AS sk_next_department,
  FIRST(sk_department) OVER (PARTITION BY sk_contact ORDER BY ts_task_created) AS sk_first_department,
  FIRST(sk_department) OVER (PARTITION BY sk_contact ORDER BY ts_task_created DESC) AS sk_last_department,
  direction,
  channel,
  origin,
  status,
  worker_email,
  quinto_andar_phone_number,
  customer_phone_number,
  customer_email,
  average_reply_time,
  total_talk_time,
  total_queue_time,
  total_wrap_up_time,
  total_waiting_time,
  first_reply_time,
  total_handling_time,
  CASE
    WHEN ROW_NUMBER() OVER(PARTITION BY sk_contact ORDER BY ts_reservation_created) = 1 THEN TRUE
    ELSE FALSE
  END AS is_first_interaction,
  CASE
    WHEN ROW_NUMBER() OVER(PARTITION BY sk_contact ORDER BY ts_reservation_created DESC) = 1 THEN TRUE
    ELSE FALSE
  END AS is_last_interaction,
  CASE
    WHEN ROW_NUMBER() OVER(PARTITION BY sk_contact, sk_department ORDER BY ts_reservation_created) = 1 THEN TRUE
    ELSE FALSE
  END AS is_first_department_interaction,
  is_per_team_task,
  is_contact_answered,
  is_interaction_answered,
  ts_task_created,
  ts_reservation_created,
  ts_reservation_ended,
  NOW() AS ts_load
FROM
  contacts
