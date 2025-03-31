WITH time_metrics AS (
  SELECT
    id_segment AS id_task,
    CASE
      WHEN SUM(total_talk_time) IS NULL THEN 0
      ELSE CAST(SUM(total_talk_time) AS FLOAT)
    END AS total_talk_time,
    CASE
      WHEN SUM(total_queue_time) IS NULL THEN 0
      ELSE CAST(SUM(total_queue_time) AS FLOAT)
    END AS total_queue_time,
    CASE
      WHEN SUM(total_wrap_up_time) IS NULL THEN 0
      ELSE CAST(SUM(total_wrap_up_time) AS FLOAT)
    END AS total_wrap_up_time,
    CASE
      WHEN SUM(total_handling_time) IS NULL THEN 0
      ELSE CAST(SUM(total_handling_time) AS FLOAT)
    END AS total_handling_time,
    CASE
      WHEN SUM(total_waiting_time) IS NULL THEN 0
      ELSE CAST(SUM(total_waiting_time) AS FLOAT)
    END AS total_waiting_time,
    CASE
      WHEN SUM(total_ring_time) IS NULL THEN 0
      ELSE CAST(SUM(total_ring_time) AS FLOAT)
    END AS total_ring_time
  FROM
    datalake_twilio_flex_insights_clean.conversation_time_metrics
  WHERE
    MAKE_DATE(year, month, day) >= DATE('{load_start_date}') - INTERVAL 2 YEAR
  GROUP BY 1
)
SELECT DISTINCT
  fcc.sk_contact,
  fcc.sk_task,
  fcc.sk_first_department,
  fcc.sk_last_department,
  fcc.sk_session,
  fcc.sk_ticket,
  fcc.sk_user,
  fcc.direction,
  fcc.channel,
  fcc.origin,
  tm.total_talk_time,
  tm.total_queue_time,
  tm.total_wrap_up_time,
  tm.total_waiting_time,
  tm.total_handling_time,
  tm.total_ring_time,
  fcc.is_contact_answered,
  fcc.ts_task_created
FROM
  dw_customer_support.fact_customer_contacts AS fcc
LEFT JOIN
  time_metrics AS tm
    ON tm.id_task = fcc.sk_task