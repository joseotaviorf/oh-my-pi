WITH email_base AS (
  SELECT DISTINCT
    ft.sk_ticket,
    cs.channel,
    da.agent_organization,
    CASE
      WHEN ft.ts_solved_local is not null then 1
      ELSE 0
    END AS is_solved,
    CASE
      WHEN dzu.role = 'agent' then 1
        ELSE 0
    END AS is_created_by_agent,
    ac.email AS agent_email,
    ac.agent_company AS cost_center,
    gdc.team AS team,
    ft.replies,
    ft.minutes_first_reply_time_business,
    ft.minutes_requester_wait_time_business,
    ft.minutes_full_resolution_time_business,
    CASE WHEN ft.minutes_first_reply_time_business <= 1440 then 1
      ELSE 0
    END AS sla_achieved_6biz_hr,
    CASE
      WHEN
        dt.tags LIKE '%resolve_ticket_acompanhamento%'
        OR dt.tags LIKE '%fechado_automaticamente_nOReply%'
        OR dt.tags LIKE '%redirecionado_atendimento_2%'
        OR dt.tags LIKE '%closed_by_merge%'
        OR dt.tags LIKE '%zapdesk%'
        OR dt.tags LIKE '%ticket_via_call%'
        OR dt.tags LIKE '%call_contato_receptivo%'
        OR dt.tags LIKE '%call_contato_ativo%'
        OR dt.tags LIKE '%resolve_ticket_acompanhamento%'
        OR dt.tags LIKE '%redirecionado_adm_v1%'
        OR dzu.email = 'notifier@tokkobroker.com'
        OR dzu.email = 'notificaciones@inmuebles24.com'
        OR dzu.email = '@usuarios.inmuebles24.com'
        OR dt.tags LIKE '%action_visits_tokko_i24%'
      THEN 1
      ELSE 0
        END AS has_exclude_tags,
    CASE
      WHEN
        dt.tags LIKE '%resolve_ticket_acompanhamento%'
        OR dt.tags LIKE '%fechado_automaticamente_noreply%'
        OR dt.tags LIKE '%redirecionado_atendimento_2%'
        OR dt.tags LIKE '%zapdesk%'
        OR dt.tags LIKE '%ticket_via_call%'
        OR dt.tags LIKE '%call_contato_receptivo%'
        OR dt.tags LIKE '%call_contato_ativo%'
        OR dt.tags LIKE '%resolve_ticket_acompanhamento%'
        OR dt.tags LIKE '%redirecionado_adm_v1%'
      THEN 1
      ELSE 0
    END AS has_retention_tags,
    CASE
      WHEN dt.tags NOT LIKE '%closed_by_merge%' then 1
      ELSE 0
    END AS has_merged_tags,
    cs.front_or_back AS front_or_back,
    cs.main_department AS main_department,
    HOUR(cs.ts_started) AS hour_started,
    HOUR(ft.ts_solved_local) AS hour_solved,
    ft.ts_solved_local,
    cs.ts_started
  FROM dw_tickets.fact_tickets AS ft
    LEFT JOIN
      dw_customer_support.dim_ticket AS dt
        ON dt.sk_ticket = ft.sk_ticket
    LEFT JOIN
      dw_customer_support.dim_zendesk_user AS dzu
        ON ft.sk_zendesk_submitter_user = dzu.sk_zendesk_user
    LEFT JOIN
      dw_customer_support.dim_department gdc
        ON dt.group_name = gdc.department
    LEFT JOIN
        dw_customer_support.dim_agent ac
          ON ft.sk_agent = ac.sk_agent
    LEFT JOIN
      dw_customer_support.fact_ticket AS cs
        ON ft.sk_ticket = cs.sk_ticket
    LEFT JOIN
      dw_customer_support.dim_agent AS da
        ON da.sk_agent = ft.sk_agent
  WHERE
    cs.channel IN ('email', 'form_faq', 'web', 'other')
    AND (DATE(ft.ts_solved_local) BETWEEN DATE_TRUNC('MONTH', DATE('{load_start_date}')) - INTERVAL '6' MONTH AND DATE('{load_end_date}')
      OR DATE(cs.ts_started) BETWEEN DATE_TRUNC('MONTH', DATE('{load_start_date}')) - INTERVAL '6' MONTH AND DATE('{load_end_date}'))
    
    AND team IS NOT NULL
)
SELECT
  sk_ticket,
  agent_email,
  team,
  main_department,
  has_exclude_tags,
  front_or_back,
  CASE
    WHEN cost_center ILIKE 'Concentrix' THEN 'Concentrix'
    WHEN cost_center ILIKE 'Atento' THEN 'Atento'
    WHEN cost_center ILIKE 'QuintoAndar' THEN 'QuintoAndar'
    ELSE NULL
	END AS company,
	channel,
	has_retention_tags,
	CASE
    WHEN
      replies > 0
      AND minutes_first_reply_time_business IS NOT NULL
    THEN sla_achieved_6biz_hr
	END AS sla_frt_achieved,
  CASE
    WHEN
      replies > 0
      AND (minutes_requester_wait_time_business / replies) <= 1440 THEN 1
    WHEN
      replies > 0
      AND (minutes_requester_wait_time_business / replies) > 1440 THEN 0
	END AS sla_rwt_achieved,
	SUM(is_solved) as solved,
	SUM(replies) as replies,
	SUM(minutes_requester_wait_time_business) as sum_rwt_min,
	hour_started,
	hour_solved,
  ts_started,
  ts_solved_local,
  YEAR(ts_solved_local) AS year,
  MONTH(ts_solved_local) AS month,
  DAY(ts_solved_local) AS day,
  NOW() AS ts_load
FROM email_base
WHERE
  front_or_back = 'front'
  AND has_exclude_tags = 0
  AND agent_organization IN ('atn','atento')
  AND main_department IN (
    'CX Visitas N1 & N2 [VIS] [PRE] [FRONT] [OUT]',
    'CX PROPOSTAS CALL/CHAT [PRO][PRE][FRONT]',
    'Consultores imobiliários 5A',
    'CX Plaquinhas [FRONT] [PRE]',
    'CX Entrada no imóvel [ONB] [POS] [FRONT]',
    'CX Pagamentos N1 [PAY] [POS] [FRONT]',
    'CX Durante a locação e reparos [POS] [FRONT]',
    'CX Rescisão e Vistoria [OFF] [POS] [FRONT]',
    '[MX] CX Front [front] [pre] [pos]',
    '[MX] CX Back [back] [pre] [pos]' ,
    'PARTNERS/CIQ [FRONT] [PRE]')
GROUP BY ALL
