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
    id_task,
    id_reservation,
    id_user,
    queue_name,
    CASE
      WHEN channel_type = 'call-in-app' THEN 'CALL IN APP'
      WHEN direction = 'outbound' THEN 'CALL OUTBOUND'
      WHEN direction = 'inbound' THEN 'CALL INBOUND'
      ELSE NULL
    END AS direction,
    'CALL' AS channel,
    CASE
      WHEN id_reservation IS NULL THEN 'ABANDONED'
      WHEN ROW_NUMBER() OVER(PARTITION BY id_task ORDER BY ts_task_created DESC) = 1 THEN 'COMPLETED'
      ELSE 'TRANSFERRED'
    END AS status,
    worker_email,
    CASE
      WHEN direction = 'inbound' THEN from_phone_number
      WHEN direction = 'outbound' THEN to_phone_number
    END AS customer_phone_number,
    NULL AS customer_email,
    NULL AS is_per_team_task,
    is_reservation_answered AS is_answered,
    ts_task_created,
    ts_reservation_created,
    ts_reservation_ended
  FROM
    datalake_customer_support_test.calls
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_star_date}' AND '{load_end_date}'
  UNION ALL
  SELECT DISTINCT
    id_session,
    id_task,
    NULL AS id_reservation,
    id_user,
    queue_name,
    'CHAT' AS channel,
    'CHAT' AS direction,
    CASE
      WHEN task_completion_reason = 'task idled' THEN 'IDLED'
      WHEN task_completion_reason = 'session expired' THEN 'EXPIRED'
      WHEN task_completion_reason = 'task completed' THEN 'COMPLETED'
      WHEN task_completion_reason = 'task transferred' THEN 'TRANSFERRED'
      WHEN ROW_NUMBER() OVER(PARTITION BY id_session ORDER BY ts_created DESC) = 1 THEN 'COMPLETED'
      ELSE 'TRANSFERRED'
    END AS status,
    worker_email,
    customer_phone_number,
    customer_email,
    is_per_team_task,
    CASE
      WHEN task_status = 'canceled' THEN FALSE
      WHEN task_completion_reason = 'Task TTL Exceeded or Max assignment count exceeded' THEN FALSE
      ELSE TRUE
    END AS is_answered,
    ts_created AS ts_task_created,
    NULL AS ts_reservation_created,
    NULL AS ts_reservation_ended
  FROM
    datalake_customer_support_test.chats
  WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_star_date}' AND '{load_end_date}'
),
contacts AS (
  SELECT
    MD5(
      CONCAT(
        d.channel,
        d.id_session,
        d.id_task
      )
    ) AS sk_contact,
    MD5(
      CONCAT(
        d.direction,
        d.id_session,
        d.id_task,
        IFNULL(d.id_reservation, '')
      )
    ) AS sk_interaction,
    MD5(d.queue_name) AS sk_department,
    d.id_session,
    d.id_task,
    d.id_reservation,
    d.id_user,
    d.queue_name,
    d.channel,
    d.direction,
    d.status,
    d.worker_email,
    d.customer_phone_number,
    d.customer_email,
    art.average_reply_time,
    tm.total_talk_time,
    tm.total_queue_time,
    tm.total_wrap_up_time,
    tm.total_waiting_time,
    tm.first_reply_time,
    tm.total_handling_time,
    d.is_per_team_task,
    d.is_answered,
    d.ts_task_created,
    d.ts_reservation_created,
    d.ts_reservation_ended
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
      AND d.channel = 'CHAT'
)
SELECT
  sk_contact,
  sk_interaction,
  COALESCE(id_user, -1) AS sk_user,
  sk_department,
  LAG(sk_department) OVER(PARTITION BY sk_contact ORDER BY ts_task_created) AS sk_from_department,
  LEAD(sk_department) OVER(PARTITION BY sk_contact ORDER BY ts_task_created) AS sk_to_department,
  direction,
  channel,
  status,
  worker_email,
  customer_phone_number,
  customer_email,
  average_reply_time
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
  is_answered,
  ts_task_created,
  ts_reservation_created,
  ts_reservation_ended
FROM
  contacts
