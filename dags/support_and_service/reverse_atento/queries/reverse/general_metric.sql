SELECT DISTINCT
  ft.sk_ticket,
  ft.sk_last_agent AS sk_agent,
  ft.channel,
  ft.csat_score,
  ft.status,
  CASE
    WHEN ft.csat_score BETWEEN 4 AND 5 THEN 'Satisfied'
    WHEN ft.csat_score = 3 THEN 'Neutral'
    WHEN ft.csat_score BETWEEN 1 AND 2 THEN 'Dissatisfied'
    ELSE NULL
  END AS csat_type,
  ft.csat_comment,
  ft.main_department,
  dc.direction,
  dd.area,
  dd.department,
  dd.journey_step,
  ft.front_or_back,
  dd.team,
  dt.motivation AS contact_motivation_tag,
  dt.theme_detail AS contact_theme_detail_tag,
  dt.customer_type_tag,
  dtt.tags AS tag,
  dt.step_tag,
  CONCAT('https://quintoandar.zendesk.com/agent/tickets/', ft.sk_ticket) AS external_url,
  ROUND(CAST(ft.full_resolution_time/60.0 AS DOUBLE), 2) AS hours_to_solve_ticket,
  da.full_name AS agent_full_name,
  da.email AS agent_email,
  da.agent_company,
  ft.reopens,
  ft.replies,
  dd.is_active,
  ft.has_answered_csat,
  ft.has_transfers,
  ft.resolution_survey AS is_resolution,
  ft.ts_started,
  ft.ts_survey,
  ft.ts_csat_response,
  ft.ts_solved,
  ft.ts_closed,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day
FROM
  dw_customer_support.fact_ticket AS ft
LEFT JOIN
  dw_customer_support.dim_channel AS dc
    ON ft.sk_channel = dc.sk_channel
LEFT JOIN
  dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
LEFT JOIN
  dw_customer_support.dim_ticket_tags AS dtt
    ON ft.sk_tags = dtt.sk_tags
LEFT JOIN
  dw_customer_support.dim_taxonomy AS dt
    ON ft.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN
  dw_customer_support.dim_agent AS da
    ON ft.sk_last_agent = da.sk_agent
WHERE
  DATE(ft.ts_started) >= DATE('2022-01-01')
AND
  ft.main_department IN (
    'Entrada no imóvel [ONB] [POS] [BACK]',
    'Proteção QuintoAndar [OFF] [POS] [BACK]',
    'Reparos [REP] [POS] [BACK]',
    'BACK [Visitas]',
    'BACK [Propostas]',
    'Aditivos [REP] [POS] [BACK]',
    'CX Negociação de aluguel [PAY] [POS] [BACK]',
    'CX Partners [PRE] [FRONT]',
    'CX Visitas  Tarefas [PRE][BACK]',
    'CX Partners Tarefas [PRE] [BACK]',
    'CX Propostas Tarefas [PRE] [BACK]',
    'CX Pagamentos Ativo [POS] [BACK] [PAY]',
    'Consultores Imobiliarios QuintoAndar [PRE] [BACK]',
    'Offboarding [OFF] [POS] [BACK]',
    'Rescisão - Despejo [OFF][POS][BACK]',
    'Offboarding Reparos [OFF] [POS] [BACK]',
    'CX Ação Plaquinhas [PRE] [BACK]',
    'Contas de Consumo [ONB] [POS] [BACK]',
    'Reparos Atento [REP] [POS] [BACK]',
    'CX Partners [PRE] [BACK]',
    'CIQ Assessor de Proprietário [PRE][BACK]',
    'CX Closing [BACK] [PRE]',
    'CX Offboarding ETP 1 [BACK] [POS]',
    'CX Rescisão [BACK] [POS]',
    'CX Onboarding [BACK] [POS]',
    'CX Vistoria [BACK]',
    'Reparos N2 - Emergenciais [QA]',
    'Reparos Urgentes [Back]',
    'Reparos Back [ATN]',
    'Triagem Reparos [Back]',
    'PARTNERS/CIQ [FRONT] [PRE]',
    'Reparos Comuns [Back]',
    'Assessor de Proprietário [ASP] [PRE] [BACK]',
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
    'MX_Socio_Inspector',
    '[MX] CX Front [front] [pre] [pos]',
    '[MX] CX Back [back] [pre] [pos]'
  )
