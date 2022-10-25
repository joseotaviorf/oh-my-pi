SELECT DISTINCT
  dmt.sk_task,
  dmt.sk_agent,
  dmt.sla_target,
  dmt.origin AS channel,
  dmt.status,
  da.email AS agent_email,
  da.agent_company,
  dd.department,
  dd.journey_step,
  dd.front_or_back,
  dd.team,
  dd.area,
  dt.motivation AS contact_motivation_tag,
  dt.theme_detail AS contact_theme_detail_tag,
  dt.customer_type_tag,
  dt.step_tag,
  dtt.tags AS tag,
  dmt.time_spent_solved_within_sla,
  dmt.time_spent_solved_with_exceed_sla,
  dmt.days_worked,
  dmt.days_off,
  dmt.days_worked AS leadtime_day,
  dmt.is_ticket_solved_within_sla,
  dmt.is_ticket_solved_with_exceed_sla,
  dmt.is_received_demand,
  dmt.is_solved_demand,
  dmt.is_closed_demand,
  dmt.ts_started,
  dmt.ts_solved,
  dmt.ts_closed,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day
FROM
  dw_customer_support.fact_demand_metrics_tasks AS dmt
LEFT JOIN
  dw_customer_support.dim_department AS dd
    ON dmt.sk_main_department = dd.sk_department
LEFT JOIN
  dw_customer_support.dim_ticket_tags AS dtt
    ON dmt.sk_tags = dtt.sk_tags
LEFT JOIN
  dw_customer_support.dim_taxonomy AS dt
    ON dmt.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN
  dw_customer_support.dim_agent AS da
    ON dmt.sk_agent = da.sk_agent
WHERE
  DATE(dmt.ts_started) >= '2022-07-19'
AND
  dd.department IN (
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
    'RevisarPagamentosRescisao',
    'RescisaoPreVigencia',
    'Reparos N2 - Emergenciais [QA]',
    'Reparos Back [ATN]',
    'Triagem Reparos [Back]',
    'PARTNERS/CIQ [FRONT] [PRE]',
    'Reparos Comuns [Back]',
    'Assessor de Proprietário [ASP] [PRE] [BACK]'
  )
