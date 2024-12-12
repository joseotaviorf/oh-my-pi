WITH time_metrics AS (
  SELECT DISTINCT
    sk_ticket,
    total_handling_time / 60 AS total_minutes_handling_time,
    total_waiting_time / 60 AS total_minutes_queue_time,
    total_talk_time / 60 AS total_minutes_talk_time
  FROM
    dw_customer_support.fact_customer_contacts
),
base_tickets AS (
  SELECT DISTINCT
    ft.sk_ticket,
    ft.sk_user,
    ft.sk_main_department,
    ft.sk_taxonomy,
    LAG(ft.sk_ticket) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_created) AS sk_ticket_previous_contact,
    dzu.phone,
    da.agent_organization,
    dd.team,
    dd.department,
    dd.journey_step,
    ft.channel,
    ft.ticket_origin,
    dt.theme,
    ftc.last_csat_score AS csat_score,
    da.email,
    CASE
      WHEN LAG(ft.sk_ticket) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_created) IS NOT NULL THEN 1
      ELSE 0
    END AS recontact_flag,
    tm.total_minutes_handling_time,
    tm.total_minutes_queue_time,
    tm.total_minutes_talk_time,
    LAG(ft.channel) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_created) AS previous_contact_channel,
    LAG(dt.theme) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_created) AS previous_contact_taxonomy,
    LAG(da.email) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_created) AS previous_contact_email,
    LAG(ftc.last_csat_score) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_created) AS previous_contact_csat,
    DATEDIFF(DATE(ft.ts_created),LAG(DATE(ft.ts_created)) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_created)) AS days_since_last_contact,
    LAG(ft.ts_created) OVER(PARTITION BY dzu.phone, dd.team ORDER BY ft.ts_created) AS ts_started_previous_contact,
    ft.ts_created AS ts_started,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
  FROM
    dw_customer_support.fact_tickets AS ft
  LEFT JOIN
    dw_satisfaction_rating.fact_ticket_csat AS ftc
      ON ftc.sk_ticket = ft.sk_ticket
  LEFT JOIN
    time_metrics AS tm
      ON tm.sk_ticket = ft.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON ft.sk_main_department = dd.sk_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON ft.sk_taxonomy = dt.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_agent AS da
      ON ft.sk_last_analyst = COALESCE(da.sk_agent, da.sk_agent_twilio)
  LEFT JOIN
    dw_customer_support.dim_zendesk_user AS dzu
      ON dzu.sk_zendesk_user = ft.sk_zendesk_requester_user
  WHERE
    ft.ts_created BETWEEN DATE('{load_start_date}') - INTERVAL '1' YEAR AND DATE('{load_end_date}')
    AND dzu.phone IS NOT NULL
    AND ((ft.channel = 'chat' AND ft.direction = 'inbound')
      OR (ft.ticket_origin IN ('call inbound', 'call in app')))
    AND dd.department IN (
      'MX_PP_Anúncio',
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
      'MX_Socio_Inspector'
    )
    AND da.agent_organization IN ('atento', 'atn')
)
SELECT DISTINCT
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
      END
    ),
    0
  ) AS flag_last_completion_reason_idled
FROM
  base_tickets AS bt
LEFT JOIN
  dw_customer_support.fact_customer_contacts AS fs
    ON fs.sk_ticket = bt.sk_ticket_previous_contact
    AND fs.sk_ticket IS NOT NULL
    AND fs.is_last_interaction = True
GROUP BY
  ALL
