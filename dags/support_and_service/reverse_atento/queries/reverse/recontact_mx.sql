WITH base_tickets AS (
  SELECT DISTINCT
    ft.sk_ticket,
    ft.sk_user,
    ft.sk_main_department,
    ft.sk_taxonomy,
    LAG(ft.sk_ticket) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_started) AS sk_ticket_previous_contact,
    dzu.phone,
    da.agent_organization,
    dd.team,
    dd.department,
    dd.journey_step,
    dc.channel,
    ft.ticket_origin,
    dt.theme,
    ft.csat_score,
    da.email,
    CASE
      WHEN LAG(ft.sk_ticket) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_started) IS NOT NULL THEN 1
      ELSE 0
    END AS recontact_flag,
    ft.total_minutes_handling_time,
    ft.total_minutes_queue_time,
    ft.total_minutes_talk_time,
    LAG(dc.channel) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_started) AS previous_contact_channel,
    LAG(dt.theme) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_started) AS previous_contact_taxonomy,
    LAG(da.email) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_started) AS previous_contact_email,
    LAG(ft.csat_score) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_started) AS previous_contact_csat,
    DATEDIFF(DATE(ft.ts_started),LAG(DATE(ft.ts_started)) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_started)) AS days_since_last_contact,
    LAG(ft.ts_started) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_started) AS ts_started_previous_contact,
    ft.ts_started,
    YEAR(ft.ts_started) AS year,
    MONTH(ft.ts_started) AS month,
    DAY(ft.ts_started) AS day,
    NOW() AS ts_load
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
      dw_customer_support.dim_agent AS da
        ON ft.sk_last_agent = COALESCE(da.sk_agent, da.sk_agent_twilio)
    INNER JOIN
      dw_tickets.fact_tickets AS fts
        ON ft.sk_ticket = fts.sk_ticket
    LEFT JOIN
      dw_customer_support.dim_zendesk_user AS dzu
        ON dzu.sk_zendesk_user = fts.sk_zendesk_requester_user
  WHERE
      ft.ts_started BETWEEN DATE('{load_start_date}') - INTERVAL '1' YEAR AND DATE('{load_end_date}')
      AND dzu.phone IS NOT NULL
      AND ((dc.channel = 'chat' AND dc.direction = 'inbound')
        OR (ft.ticket_origin IN ('call inbound', 'call inapp')))
      AND dd.department IN
        ('MX_PP_Anúncio',
        'MX_PP_Visitas',
        'MX_PP_Contrato',
        'MX_PP_Administrativo',
        'MX_IQ_Visitas',
        'MX_IQ_Contratos',
        'MX_IQ_Administrativo',
        'MX_Socio_Agente',
        'MX_Socio_Fotógrafos',
        'MX_Socio_Refere_y_Gaña',
        'MX_Socio_Otros',
        'MX_Socio_Inspector')
      AND da.agent_organization IN ('atento', 'atn')
)
SELECT
  bt.sk_ticket,
  bt.sk_user,
  bt.sk_main_department,
  bt.sk_taxonomy,
  bt.sk_ticket_previous_contact,
  bt.phone,
  bt.agent_organization,
  bt.team,
  bt.department,
  bt.journey_step,
  bt.channel,
  bt.ticket_origin,
  bt.theme,
  bt.recontact_flag,
  bt.csat_score,
  bt.email,
  bt.total_minutes_handling_time,
  bt.total_minutes_queue_time,
  bt.total_minutes_talk_time,
  bt.previous_contact_channel,
  bt.previous_contact_taxonomy,
  bt.previous_contact_email,
  bt.previous_contact_csat,
  bt.days_since_last_contact,
  bt.ts_started_previous_contact,
  bt.ts_started,
  bt.year,
  bt.month,
  bt.day,
  bt.ts_load,
  COALESCE(
    MAX(
      CASE
        WHEN fs.completion_reason = 'task idled' THEN 1
        ELSE 0
      END)
    ,0) AS flag_last_completion_reason_idled
FROM
  base_tickets AS bt
  LEFT JOIN
    dw_customer_support.fact_segment AS fs
      ON fs.sk_ticket = bt.sk_ticket_previous_contact
      AND fs.sk_ticket IS NOT NULL
      AND fs.is_last_segment = True
GROUP BY
  ALL
