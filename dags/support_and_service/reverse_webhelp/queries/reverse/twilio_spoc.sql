WITH segments_perspective AS (
    SELECT
      fcc.sk_interaction,
      fcc.sk_session,
      fcc.sk_task,
      fcc.sk_ticket,
      fcc.sk_user,
      fcc.channel,
      fcc.is_last_interaction,
      UPPER(fcc.status) status,
      dd.department,
      da.email AS agent_email,
      fcc.first_reply_time AS first_response_time,
      fcc.total_queue_time AS queue_time,
      fcc.total_talk_time AS talk_time,
      dd_last.department AS last_department,
      dd_first.department AS first_department,
      dd_prev.department AS transferred_from,
      dd_next.department AS transferred_to,
      fcc.ts_task_created - interval '3' hour AS ts_created,
      fcc.is_spoc_task,
      fcc.direction as spoc_direction
    FROM
      dw_customer_support.fact_customer_contacts AS fcc
    LEFT JOIN 
      dw_customer_support.dim_department AS dd
        ON dd.sk_department = fcc.sk_department
    LEFT JOIN 
      dw_customer_support.dim_department AS dd_last
        ON dd_last.sk_department = fcc.sk_last_department
    LEFT JOIN 
      dw_customer_support.dim_department AS dd_first
        ON dd_first.sk_department = fcc.sk_first_department 
    LEFT JOIN 
      dw_customer_support.dim_department AS dd_prev
        ON dd_prev.sk_department = fcc.sk_prev_department 
    LEFT JOIN 
      dw_customer_support.dim_department AS dd_next
        ON dd_next.sk_department = fcc.sk_next_department
    LEFT JOIN 
      dw_customer_support.dim_analyst AS da 
        ON da.sk_analyst = fcc.sk_analyst
    WHERE 
      fcc.channel IN ('chat', 'call')
      AND fcc.origin NOT IN ('outbound')
      AND fcc.ts_task_created >= date('2025-01-01')
  )

,started_and_ended_chat_time AS (

SELECT
  mq.sk_session,
  mq.talk_time,
  DATE_FORMAT(fcc.ts_reservation_created, 'HH:mm:ss') AS chat_started_time,
  DATE_FORMAT(NVL(DATE_ADD(SECOND, CAST(mq.talk_time AS INTEGER), fcc.ts_reservation_created),
                fcc.ts_reservation_created),'HH:mm:ss') AS chat_ended_time,
  ROW_NUMBER() OVER(PARTITION BY mq.sk_session ORDER BY fcc.ts_reservation_created) rn_inicio

FROM segments_perspective mq
LEFT JOIN dw_customer_support.fact_customer_contacts fcc
  ON mq.sk_session = fcc.sk_session

)

, final AS (SELECT 
  mq.spoc_direction,
  DATE(mq.ts_created) ts_created,
  mq.first_response_time,
  mq.queue_time,
  mq.talk_time,
  IF(mq.agent_email LIKE '%webhelp%', mq.agent_email, NULL) spoc_agent_email,
  mq.status,
  mq.sk_ticket,
  mq.sk_user,
  mq.transferred_to,
  mq.transferred_from,
  mq.sk_task,
  mq.sk_session,
  mq.sk_interaction,
  sec_inicio.chat_started_time,
  sec_inicio.chat_ended_time,
  ROUND(AVG(fcm.reply_time), 0) avg_reply_time,
  IF(sec_inicio.chat_started_time BETWEEN DATE_FORMAT('09:00:00', 'HH:mm:ss') AND DATE_FORMAT('17:00:00', 'HH:mm:ss') AND DAYOFWEEK(DATE(mq.ts_created)) BETWEEN 2 AND 6, TRUE, FALSE) workday_chat

FROM segments_perspective mq
LEFT JOIN dw_customer_support.fact_chat_messages fcm
  ON mq.sk_session = fcm.sk_session
LEFT JOIN started_and_ended_chat_time sec_inicio
  ON mq.sk_session = sec_inicio.sk_session AND sec_inicio.rn_inicio = 1
WHERE mq.is_spoc_task = TRUE

GROUP BY
  mq.spoc_direction,
  DATE(mq.ts_created),
  mq.first_response_time,
  mq.queue_time,
  mq.talk_time,
  spoc_agent_email,
  mq.status,
  mq.sk_ticket,
  mq.sk_user,
  mq.transferred_to,
  mq.transferred_from,
  mq.sk_task,
  mq.sk_session,
  mq.sk_interaction,
  sec_inicio.chat_started_time,
  sec_inicio.chat_ended_time,
  workday_chat
)
SELECT
spoc_direction,
ts_created,
first_response_time,
queue_time,
talk_time,
spoc_agent_email,
status,
sk_ticket,
sk_user,
transferred_to,
transferred_from,
sk_task,
sk_session,
sk_interaction,
chat_started_time,
chat_ended_time,
avg_reply_time,
YEAR(CURRENT_DATE - 1) AS year,
MONTH(CURRENT_DATE - 1) AS month,
DAY(CURRENT_DATE - 1) AS day,
NOW() AS ts_load
FROM final
where workday_chat = TRUE
