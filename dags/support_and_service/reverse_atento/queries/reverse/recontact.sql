WITH front_tickets_list AS (
  SELECT DISTINCT
    ft.sk_ticket,
    ft.sk_user,
    ft.sk_main_department,
    ft.sk_taxonomy,
    da.agent_organization,
    COALESCE(da.email, da2.email) AS email,
    ft.channel,
    CASE
      WHEN ft.ticket_origin = 'call inapp' THEN UPPER(dc.direction)
      WHEN ft.ticket_origin IN ('call inbound', 'chat5a') THEN 'INBOUND'
      WHEN ft.ticket_origin = 'call outbound' THEN 'OUTBOUND'
      ELSE UPPER(dc.direction)
    END AS refined_direction,
    dd.team,
    dd.department,
    dd.journey_step,
    ft.ticket_origin,
    dt.theme,
    dt.theme_detail,
    ft.csat_score,
    ft.total_minutes_handling_time,
    ft.total_minutes_queue_time,
    ft.total_minutes_talk_time,
    DATE_ADD(DAY, -3, ft.ts_started) AS search_window_from,
    ft.ts_started
  FROM
    dw_customer_support.fact_ticket AS ft
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON ft.sk_main_department = dd.sk_department
  LEFT JOIN
    dw_customer_support.dim_channel AS dc
      ON ft.sk_channel = dc.sk_channel
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON ft.sk_taxonomy = dt.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_agent as da
      ON ft.sk_last_agent = da.sk_agent
  LEFT JOIN
    dw_customer_support.dim_agent as da2
      ON ft.sk_last_agent = da2.sk_agent_twilio
  WHERE
    ft.sk_user IS NOT NULL
    AND dd.area = 'CX'
    AND ft.front_or_back = 'front'
    AND ft.channel IN ('call', 'chat')
)
,recontact_check AS (
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
    DATE_DIFF(
      DAY,
      LAG(DATE(rc.ts_started)) OVER(PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started),
      DATE(rc.ts_started)
    ) AS days_since_last_contact,
    rc.theme,
    rc.theme_detail,
    CASE
      WHEN DATE_DIFF(DAY, LAG(DATE(rc.ts_started)) OVER(PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started), DATE(rc.ts_started)) <= 3 THEN 1
      ELSE 0
    END AS recontact_flag,
    LAG(rc.sk_ticket) OVER(PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started) AS sk_ticket_previous_contact,
    LAG(rc.ts_started) OVER(PARTITION BY rc.sk_user,rc.team ORDER BY rc.ts_started) AS ts_started_previous_contact,
    LAG(rc.channel) OVER(PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started) AS previous_contact_channel,
    LAG(rc.theme) OVER(PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started) AS previous_contact_taxonomy,
    rc.csat_score,
    LAG(rc.csat_score) OVER(PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started) AS previous_contact_csat,
    rc.total_minutes_handling_time,
    rc.total_minutes_queue_time,
    rc.total_minutes_talk_time,
    rc.email,
    LAG(rc.email) OVER(PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started) AS previous_contact_email,
    rc.department,
    LEAD(rc.sk_ticket) OVER(PARTITION BY rc.sk_user ORDER BY rc.ts_started) AS sk_ticket_contact_later,
    LAG(rc.total_minutes_handling_time) OVER(PARTITION BY rc.sk_user ORDER BY rc.ts_started) AS total_minutes_handling_time_previous_contact,
    rc.refined_direction,
    CAST(rc.sk_user AS STRING) || '-' ||
    CASE
      WHEN rc.department IN (
        'CX Mudança [FRONT] [POS]',
        'CX Parceiros Compra e Venda [FRONT]',
        'CX Parceiros [FRONT] [PRE]',
        'CX Parceiros da Portaria [FRONT] [PRE]',
        'CX Propostas [FRONT] [PRE]',
        'CX Visitas [FRONT] [PRE]',
        'Consultores imobiliários 5A',
        'CX Pagamentos [FRONT] [POS]',
        'CX Reparos [FRONT] [POS]',
        'CX Rescisão [FRONT] [POS]'
      ) THEN 'front'
    END AS unificador_front,
    rc.ts_started
  FROM
    front_tickets_list AS rc

  WHERE
    ts_started BETWEEN DATE('{load_start_date}') - INTERVAL '6' MONTH AND DATE('{load_end_date}')
    AND refined_direction = 'INBOUND'
),
demand_back_FRC AS (
  SELECT DISTINCT
    ft.ts_started,
    ft.ts_solved,
    ft.sk_ticket,
    ft.sk_user,
    dd.department AS department_back,
    dd.team AS team_back,
    dc.channel,
    CAST(ft.sk_user AS STRING) || '-' ||
    CASE
      WHEN dd.department IN(
        'CX Partners Tarefas [PRE] [BACK]',
        'CX Propostas Tarefas [PRE] [BACK]',
        'Aditivos [REP] [POS] [BACK]',
        'Entrada no imóvel [ONB] [POS] [BACK]',
        'CX Pagamentos Ativo [POS] [BACK] [PAY]',
        'Alteração de dados bancários [BACK]')
      THEN 'front'
    END AS unificador_back
  FROM
    dw_customer_support.fact_ticket AS ft
  INNER JOIN
    dw_customer_support.dim_department AS dd
      ON ft.sk_main_department = dd.sk_department
  INNER JOIN
    dw_customer_support.dim_channel AS dc
      ON ft.sk_channel = dc.sk_channel
  WHERE
    ft.sk_user IS NOT NULL
    AND dd.area = 'CX'
    AND dd.department IN(
      'CX Partners Tarefas [PRE] [BACK]',
      'CX Propostas Tarefas [PRE] [BACK]',
      'Aditivos [REP] [POS] [BACK]',
      'Entrada no imóvel [ONB] [POS] [BACK]',
      'CX Pagamentos Ativo [POS] [BACK] [PAY]',
      'Alteração de dados bancários [BACK]')
    AND dd.front_or_back = 'back'
    AND ft.ts_started BETWEEN DATE('{load_start_date}') - INTERVAL '6' MONTH AND DATE('{load_end_date}')
)
SELECT
  rc.sk_ticket,
  rc.sk_ticket_previous_contact AS sk_ticket_first_contact,
  rc.sk_ticket_contact_later AS sk_ticket_contact_later,
  rc.sk_user,
  rc.channel,
  rc.department,
  rc.team,
  rc.email,
  rc.theme_detail,
  rc.previous_contact_taxonomy AS macrotaxo_first_contact,
  rc.theme AS macrotaxo_last_contact,
  rc.previous_contact_email AS email_first_contact,
  rc.total_minutes_handling_time,
  rc.total_minutes_handling_time_previous_contact AS total_minutes_handling_time_previous_contact,
  rc.total_minutes_queue_time,
  rc.previous_contact_csat AS csat_first_contact,
  rc.csat_score,
  ARRAY_JOIN(
    ARRAY_AGG(
      CASE
        WHEN rc.ts_started >= DATE_TRUNC('hour', db.ts_started)
          AND (rc.ts_started <= DATE_TRUNC('hour', db.ts_solved)
          OR db.ts_solved IS NULL)
        THEN CAST(db.sk_ticket AS STRING)
      ELSE NULL
    END), '') AS ticket_back,
  recontact_flag,
  rc.search_window_from,
  rc.search_window_until,
  rc.ts_started_previous_contact AS ts_started_first_contact,
  rc.ts_started AS ts_started,
  refined_direction,
  YEAR(rc.ts_started) AS year,
  MONTH(rc.ts_started) AS month,
  DAY(rc.ts_started) AS day,
  NOW() AS ts_load
FROM
  recontact_check AS rc
LEFT JOIN
  demand_back_FRC AS db
    ON rc.unificador_front = db.unificador_back
WHERE
  department NOT LIKE '%[WH]%' --caixas da WebHelp agora são identificadas assim
  AND department NOT LIKE '%[CNX]%'
  AND agent_organization IN ('atn', 'atento')
GROUP BY ALL