WITH time_metrics AS (
  SELECT DISTINCT
    sk_ticket,
    total_handling_time / 60 AS total_minutes_handling_time,
    total_waiting_time / 60 AS total_minutes_queue_time,
    total_talk_time / 60 AS total_minutes_talk_time
  FROM dw_customer_support.fact_customer_contacts
  WHERE
    CAST(ts_task_created AS DATE) BETWEEN DATE_TRUNC('MONTH', CAST('{load_start_date}' AS DATE)) - INTERVAL '6' MONTH AND CAST('{load_end_date}' AS DATE)
), front_tickets_list AS (
  SELECT DISTINCT
    ft.sk_ticket,
    ft.sk_user,
    ft.sk_main_department,
    ft.sk_taxonomy,
    da.agent_organization,
    COALESCE(da.email, da2.email) AS email,
    ft.channel,
    CASE
      WHEN ft.ticket_origin = 'call inapp'
      THEN UPPER(ft.direction)
      WHEN ft.ticket_origin IN ('call inbound', 'chat5a')
      THEN 'INBOUND'
      WHEN ft.ticket_origin = 'call outbound'
      THEN 'OUTBOUND'
      ELSE UPPER(ft.direction)
    END AS refined_direction,
    dd.team,
    dd.department,
    dd.journey_step,
    ft.ticket_origin,
    dt.theme,
    dt.theme_detail,
    ftc.last_csat_score AS csat_score,
    tm.total_minutes_handling_time,
    tm.total_minutes_queue_time,
    tm.total_minutes_talk_time,
    DATE_ADD(ft.ts_created, -3) AS search_window_from,
    ft.ts_created AS ts_started
  FROM dw_customer_support.fact_tickets AS ft
  LEFT JOIN dw_satisfaction_rating.fact_ticket_csat AS ftc
    ON ftc.sk_ticket = ft.sk_ticket
  LEFT JOIN time_metrics AS tm
    ON tm.sk_ticket = ft.sk_ticket
  LEFT JOIN dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
  LEFT JOIN dw_customer_support.dim_taxonomy AS dt
    ON ft.sk_taxonomy = dt.sk_taxonomy
  LEFT JOIN dw_customer_support.dim_analyst AS da
    ON ft.sk_last_analyst = da.sk_analyst
  LEFT JOIN dw_customer_support.dim_analyst AS da2
    ON ft.sk_last_analyst = da2.sk_agent_twilio
  WHERE
    ft.sk_user <> -1
    AND dd.area = 'CX'
    AND ft.front_or_back = 'front'
    AND ft.channel IN ('call', 'chat')
), recontact_check AS (
  SELECT
    sk_ticket,
    channel,
    ticket_origin,
    sk_main_department,
    sk_taxonomy,
    sk_user,
    agent_organization,
    team,
    journey_step,
    search_window_from,
    search_window_until,
    days_since_last_contact,
    theme,
    theme_detail,
    recontact_flag,
    recontact_flag_taxo,
    sk_ticket_previous_contact,
    ts_started_previous_contact,
    previous_contact_channel,
    previous_contact_taxonomy,
    csat_score,
    previous_contact_csat,
    total_minutes_handling_time,
    total_minutes_queue_time,
    total_minutes_talk_time,
    email,
    previous_contact_email,
    department,
    sk_ticket_contact_later,
    total_minutes_handling_time_previous_contact,
    refined_direction,
    unificador_front,
    ts_started
  FROM (
    SELECT
      rc.sk_ticket,
      rc.channel,
      rc.ticket_origin,
      rc.sk_main_department,
      rc.sk_taxonomy,
      rc.sk_user,
      rc.agent_organization,
      rc.team,
      rc.journey_step,
      rc.search_window_from,
      rc.ts_started AS search_window_until,
      DATEDIFF(
        TO_DATE(CAST(rc.ts_started AS DATE)),
        TO_DATE(
          CASE
            WHEN rc.ts_started <> LAG(rc.ts_started) OVER (PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started)
            THEN LAG(CAST(rc.ts_started AS DATE)) OVER (PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started)
            ELSE NULL
          END
        )
      ) AS days_since_last_contact,
      rc.theme,
      rc.theme_detail,
      CASE
        WHEN DATEDIFF(
          TO_DATE(CAST(rc.ts_started AS DATE)),
          TO_DATE(
            LAG(CAST(rc.ts_started AS DATE)) OVER (PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started)
          )
        ) <= 3
        AND rc.ts_started <> LAG(rc.ts_started) OVER (PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started)
        THEN 1
        ELSE 0
      END AS recontact_flag,
      CASE
        WHEN rc.theme IS NULL
        THEN 0
        WHEN DATEDIFF(
          TO_DATE(CAST(rc.ts_started AS DATE)),
          TO_DATE(
            LAG(CAST(rc.ts_started AS DATE)) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
          )
        ) <= 3
        AND LAG(rc.ts_started) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started) <> rc.ts_started
        THEN 1
        ELSE 0
      END AS recontact_flag_taxo,
      CASE
        WHEN rc.ts_started <> LAG(rc.ts_started) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        THEN LAG(rc.sk_ticket) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        ELSE NULL
      END AS sk_ticket_previous_contact,
      CASE
        WHEN rc.ts_started <> LAG(rc.ts_started) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        THEN LAG(rc.ts_started) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        ELSE NULL
      END AS ts_started_previous_contact,
      CASE
        WHEN rc.ts_started <> LAG(rc.ts_started) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        THEN LAG(rc.channel) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        ELSE NULL
      END AS previous_contact_channel,
      CASE
        WHEN rc.ts_started <> LAG(rc.ts_started) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        THEN LAG(rc.theme) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        ELSE NULL
      END AS previous_contact_taxonomy,
      rc.csat_score,
      CASE
        WHEN rc.ts_started <> LAG(rc.ts_started) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        THEN LAG(rc.csat_score) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        ELSE NULL
      END AS previous_contact_csat,
      rc.total_minutes_handling_time,
      rc.total_minutes_queue_time,
      rc.total_minutes_talk_time,
      rc.email,
      CASE
        WHEN rc.ts_started <> LAG(rc.ts_started) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        THEN LAG(rc.email) OVER (PARTITION BY rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started)
        ELSE NULL
      END AS previous_contact_email,
      rc.department,
      LEAD(rc.sk_ticket) OVER (PARTITION BY rc.sk_user ORDER BY rc.ts_started) AS sk_ticket_contact_later,
      LAG(rc.total_minutes_handling_time) OVER (PARTITION BY rc.sk_user ORDER BY rc.ts_started) AS total_minutes_handling_time_previous_contact,
      rc.refined_direction,
      CAST(rc.sk_user AS STRING) || '-' || CASE
        WHEN rc.department IN ('CX Mudança [FRONT] [POS]', 'CX Parceiros Compra e Venda [FRONT]', 'CX Parceiros [FRONT] [PRE]', 'CX Parceiros da Portaria [FRONT] [PRE]', 'CX Propostas [FRONT] [PRE]', 'CX Visitas [FRONT] [PRE]', 'Consultores imobiliários 5A', 'CX Pagamentos [FRONT] [POS]', 'CX Reparos [FRONT] [POS]', 'CX Rescisão [FRONT] [POS]')
        THEN 'front'
      END AS unificador_front,
      rc.ts_started,
      ROW_NUMBER() OVER (PARTITION BY rc.sk_ticket, rc.sk_user, rc.team, rc.theme ORDER BY rc.ts_started DESC) AS _w
    FROM front_tickets_list AS rc
    WHERE
      ts_started BETWEEN DATE_TRUNC('MONTH', CAST('{load_start_date}' AS DATE)) - INTERVAL '6' MONTH AND CAST('{load_end_date}' AS DATE)
      AND refined_direction = 'INBOUND'
  ) AS _t
  WHERE
    _w = 1
), demand_back_FRC AS (
  SELECT DISTINCT
    ft.ts_created AS ts_started,
    ft.ts_solved,
    ft.sk_ticket,
    ft.sk_user,
    dd.department AS department_back,
    dd.team AS team_back,
    CASE WHEN ft.channel = 'email' THEN 'email' ELSE ft.channel END AS channel,
    CAST(ft.sk_user AS STRING) || '-' || CASE
      WHEN dd.department IN ('CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]', 'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]', 'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]')
      THEN 'front'
    END AS unificador_back
  FROM dw_customer_support.fact_tickets AS ft
  INNER JOIN dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
  WHERE
    ft.sk_user <> -1
    AND dd.area = 'CX'
    AND dd.department IN ('CX Partners Tarefas [PRE] [BACK]', 'CX Propostas Tarefas [PRE] [BACK]', 'Aditivos [REP] [POS] [BACK]', 'Entrada no imóvel [ONB] [POS] [BACK]', 'CX Pagamentos Ativo [POS] [BACK] [PAY]', 'Alteração de dados bancários [BACK]')
    AND dd.front_or_back = 'back'
    AND ft.ts_created >= CAST('{load_start_date}' AS DATE) - INTERVAL '6' MONTH
)
SELECT
  rc.sk_ticket,
  rc.sk_ticket_previous_contact AS sk_ticket_first_contact,
  rc.sk_ticket_contact_later,
  rc.sk_user,
  rc.channel,
  rc.department,
  rc.team,
  rc.email,
  rc.agent_organization AS organization,
  rc.theme_detail,
  rc.previous_contact_taxonomy AS macrotaxo_first_contact,
  rc.theme AS macrotaxo_last_contact,
  rc.previous_contact_email AS email_first_contact,
  rc.total_minutes_handling_time,
  rc.total_minutes_handling_time_previous_contact,
  rc.total_minutes_queue_time,
  rc.previous_contact_csat AS csat_first_contact,
  rc.csat_score,
  ARRAY_JOIN(
    COLLECT_LIST(
      CASE
        WHEN rc.ts_started >= DATE_TRUNC('HOUR', db.ts_started)
        AND (
          rc.ts_started <= DATE_TRUNC('HOUR', db.ts_solved) OR db.ts_solved IS NULL
        )
        THEN CAST(db.sk_ticket AS STRING)
        ELSE NULL
      END
    ),
    ''
  ) AS ticket_back,
  recontact_flag,
  recontact_flag_taxo,
  rc.search_window_from,
  rc.search_window_until,
  rc.ts_started_previous_contact AS ts_started_first_contact,
  rc.ts_started,
  refined_direction,
  YEAR(TO_DATE(CURRENT_DATE)) AS year,
  MONTH(TO_DATE(CURRENT_DATE)) AS month,
  DAY(TO_DATE(CURRENT_DATE)) AS day,
  NOW() AS ts_load
FROM recontact_check AS rc
LEFT JOIN demand_back_FRC AS db
  ON rc.unificador_front = db.unificador_back
WHERE
  NOT department LIKE '%[WH]%' /* caixas da WebHelp agora são identificadas assim */
  AND NOT department LIKE '%[CNX]%'
GROUP BY ALL
