WITH front_tickets_list AS (
  SELECT DISTINCT
    ft.sk_ticket,
    LAG(ft.sk_ticket) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS sk_ticket_previous_contact,
    LEAD(ft.sk_ticket) OVER(PARTITION BY ft.sk_user ORDER BY ft.ts_started) AS sk_ticket_contact_later,
    ft.sk_user,
    ft.sk_main_department,
    ft.sk_taxonomy,
    da.agent_organization,
    da.email,
    dd.team,
    dd.department,
    dd.journey_step,
    dc.channel,
    ft.ticket_origin,
    dt.theme,
    dt.theme_detail,
    ft.csat_score,
    ft.total_minutes_handling_time,
    ft.total_minutes_queue_time,
    ft.total_minutes_talk_time,
    LAG(ft.total_minutes_handling_time) OVER(PARTITION BY ft.sk_user ORDER BY ft.ts_started) AS total_minutes_handling_time_previous_contact,
    CASE
      WHEN LAG(ft.sk_ticket) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) IS NOT NULL THEN 1
      ELSE 0
    END AS recontact_flag,
    LAG(dc.channel) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS previous_contact_channel,
    LAG(dt.theme) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS previous_contact_taxonomy,
    LAG(da.email) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS previous_contact_email,
    LAG(ft.csat_score) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS previous_contact_csat,
    DATE_DIFF(DATE(ft.ts_started), LAG(DATE(ft.ts_started)) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started)) AS days_since_last_contact,
    LAG(ft.ts_started) OVER(PARTITION BY ft.sk_user, dd.team ORDER BY ft.ts_started) AS ts_started_previous_contact,
    DATE_SUB(ft.ts_started, 3) AS search_window_from,
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
      OR ft.sk_last_agent = da.sk_agent_twilio
  WHERE
    ft.sk_user is NOT NULL
    AND dd.area = 'CX'
    AND ft.front_or_back = 'front'
    AND ( (dc.channel = 'chat' AND dc.direction = 'inbound')
        OR (ft.ticket_origin IN ('call inbound', 'call inapp')) )
),
tbl_completion_reason AS (
  SELECT
    fs.sk_ticket,
    MAX(CASE WHEN fs.completion_reason = 'task idled' THEN 1 ELSE 0 END) AS flag_last_completion_reason_idled
  FROM
    dw_customer_support.fact_segment AS fs
  WHERE
    fs.is_last_segment = True
  GROUP BY ALL
),
recontact_check AS (
  SELECT
    rc.sk_ticket,
    channel,
    ticket_origin,
    sk_main_department,
    sk_taxonomy,
    sk_user,
    agent_organization,
    team,
    journey_step,
    search_window_from,
    rc.ts_started AS search_window_until,
    days_since_last_contact,
    theme,
    theme_detail,
    CASE
      WHEN
        LAG(rc.sk_ticket) OVER(PARTITION BY rc.sk_user, rc.team ORDER BY rc.ts_started) IS NOT NULL
      THEN 1
      ELSE 0
    END AS recontact_flag,
    sk_ticket_previous_contact,
    ts_started_previous_contact,
    previous_contact_channel,
    COALESCE(flag_last_completion_reason_idled,0) AS flag_last_completion_reason_idled,
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
    CAST(sk_user AS STRING) || '-' ||
        CASE
        WHEN department IN (
          'CX Mudança [FRONT] [POS]',
          'CX Parceiros Compra e Venda [FRONT]',
          'CX Parceiros [FRONT] [PRE]',
          'CX Parceiros da Portaria [FRONT] [PRE]',
          'CX Propostas [FRONT] [PRE]',
          'CX Visitas [FRONT] [PRE]',
          'Consultores imobiliários 5A',
          'CX Pagamentos [FRONT] [POS]',
          'CX Reparos [FRONT] [POS]',
          'CX Rescisão [FRONT] [POS]')
          THEN 'front'
    END AS unificador_front
    ts_started,
  FROM
    front_tickets_list AS rc
  LEFT JOIN
    tbl_completion_reason
      ON tbl_completion_reason.sk_ticket = rc.sk_ticket_previous_contact
      AND tbl_completion_reason.sk_ticket IS NOT NULL
  WHERE
    ts_started >= current_date - interval '45' day
    AND department NOT LIKE '%[WH]%' --caixas da WebHelp agora são identificadas assim
    AND department NOT LIKE '%[CNX]%'
    AND agent_organization IN ('atn','atento')
),
demand_back_FRC AS (
  SELECT DISTINCT
    ft.ts_started,
    ft.ts_solved,
    ft.sk_ticket,
    ft.sk_user,
    dd.department as department_back,
    dd.team as team_back,
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
    AND ft.ts_started >= CURRENT_DATE - INTERVAL '6' month

)
SELECT
  rc.sk_ticket,
  rc.sk_ticket_previous_contact AS sk_ticket_first_contact,
  rc.sk_ticket_contact_later as sk_ticket_contact_later,
  rc.sk_user,
  rc.channel,
  rc.team,
  rc.email,
  rc.theme_detail,
  rc.previous_contact_taxonomy AS macrotaxo_first_contact,
  rc.theme as macrotaxo_last_contact,
  rc.previous_contact_email AS email_first_contact,
  rc.total_minutes_handling_time,
  rc.total_minutes_handling_time_previous_contact as total_minutes_handling_time_previous_contact,
  rc.total_minutes_queue_time,
  rc.previous_contact_csat as csat_first_contact,
  rc.csat_score,
  ARRAY_JOIN(
    ARRAY_AGG(
      CASE
        WHEN rc.ts_started >= DATE_TRUNC('hour', db.ts_started)
          AND (rc.ts_started <= DATE_TRUNC('hour', db.ts_solved)
          OR db.ts_solved IS NULL)
      THEN CAST(db.sk_ticket AS STRING)
      ELSE NULL END), '') AS ticket_back,
  CASE
    WHEN days_since_last_contact <= '3' THEN recontact_flag
    ELSE 0
  END AS recontact_flag,
  rc.search_window_from,
  rc.search_window_until,
  rc.ts_started_previous_contact AS ts_started_first_contact,
  rc.ts_started as ts_started
FROM
  recontact_check AS rc
LEFT JOIN
  demand_back_FRC AS db
    ON rc.unificador_front = db.unificador_back
GROUP BY ALL