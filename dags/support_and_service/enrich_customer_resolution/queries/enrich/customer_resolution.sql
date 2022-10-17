WITH front_tickets AS (
  SELECT
    id_ticket,
    MAX(id_user) AS id_user,
    "call" AS ticket_channel,
    dc.team AS team,
    direction,
    status,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed
  FROM
    datalake_customer_support.call AS cl
  INNER JOIN
    datalake_gsheets_clean.department_control AS dc
      ON cl.last_department = dc.department
  WHERE
    id_user > -1
    AND ts_ticket_started IS NOT NULL
    AND dc.team IS NOT NULL
    AND cl.tags NOT LIKE '%atendimento_escalado%'
    AND (
      cl.front_or_back = 'front'
      OR cl.front_or_back IS NULL
    )
    AND (
      direction = 'inbound'
      OR direction IS NULL
    )
  GROUP BY 1,3,4,5,6,7,8
  UNION ALL
  SELECT
    id_ticket,
    MAX(id_user) AS id_user,
    "chat" AS ticket_channel,
    dc.team AS team,
    "inbound" AS direction,
    status,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed
  FROM
    datalake_customer_support.chat AS ch
  INNER JOIN
    datalake_gsheets_clean.department_control AS dc
      ON ch.last_department = dc.department
  WHERE
    id_user > -1
    AND ts_ticket_started IS NOT NULL
    AND dc.team IS NOT NULL
    AND ch.tags NOT LIKE '%atendimento_escalado%'
    AND (
      ch.front_or_back = 'front'
      OR ch.front_or_back IS NULL
    )
  GROUP BY 1,3,4,5,6,7,8
  UNION ALL
  SELECT
    id_ticket,
    MAX(id_user) AS id_user,
    "email" AS ticket_channel,
    dc.team AS team,
    direction,
    status,
    ts_ticket_started AS ts_started,
    ts_ticket_ended AS ts_closed
  FROM
    datalake_customer_support.email AS em
  INNER JOIN
    datalake_gsheets_clean.department_control AS dc
      ON em.department = dc.department
  WHERE
    id_user > -1
    AND ts_ticket_started IS NOT NULL
    AND dc.team IS NOT NULL
    AND em.tags NOT LIKE '%atendimento_escalado%'
    AND (
      em.front_or_back = 'front'
      OR em.front_or_back IS NULL
    )
    AND (
      direction = 'inbound'
      OR direction IS NULL
    )
  GROUP BY 1,3,4,5,6,7,8
),
user_recontacts AS (
  SELECT DISTINCT
    ft.id_ticket,
    ft.id_user,
    ft.team,
    CASE
      WHEN ((BIGINT(ts_started) - BIGINT(LAG(ts_started, 1) OVER(PARTITION BY id_user, team ORDER BY ts_started)))/(3600)) < 168 THEN 1
      ELSE 0
    END AS is_recontact,
    CASE
      WHEN ((BIGINT(ts_started) - BIGINT(LAG(ts_started, 1) OVER(PARTITION BY id_user, team ORDER BY ts_started)))/(3600)) < 168 THEN NULL
      ELSE id_ticket
    END AS main_ticket,
    ft.ts_started
  FROM
    front_tickets AS ft
),
ticket_sessions AS (
  SELECT
    id_ticket,
    MAX(main_ticket) OVER(PARTITION BY id_user, team ORDER BY ts_started ASC ROWS UNBOUNDED PRECEDING) AS ticket_session,
    id_user,
    is_recontact,
    ts_started
  FROM
    user_recontacts
),
tickets_by_ticket_session AS (
  SELECT
    ticket_session,
    id_user,
    COUNT(DISTINCT id_ticket) AS total_tickets,
    MIN(ts_started) AS ts_started
  FROM
    ticket_sessions
  GROUP BY 1,2
),
ticket_recontact_list AS (
  SELECT DISTINCT
    ticket_session,
    id_user,
    COLLECT_LIST(id_ticket) OVER (PARTITION BY ticket_session ORDER BY ts_started ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS ticket_recontact_list
  FROM
    ticket_sessions
)
SELECT
    tts.ticket_session AS id_ticket,
    tts.id_user,
    ft.ticket_channel,
    tts.total_tickets,
    team,
    trl.ticket_recontact_list,
    CASE
      WHEN tts.total_tickets > 1 THEN FALSE
      ELSE TRUE
    END AS is_fcr,
    ft.ts_started,
    ft.ts_closed
FROM
    tickets_by_ticket_session AS tts
LEFT JOIN
    ticket_recontact_list AS trl
      ON tts.ticket_session = trl.ticket_session
      AND tts.id_user = trl.id_user
LEFT JOIN
    front_tickets AS ft
      ON ft.id_ticket = tts.ticket_session
WHERE
    status = 'closed'
