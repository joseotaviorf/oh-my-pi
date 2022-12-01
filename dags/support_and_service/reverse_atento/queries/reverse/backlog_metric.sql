SELECT DISTINCT
  bmt.sk_task AS sk_ticket,
  bmt.sk_agent,
  bmt.origin AS channel,
  da.agent_company,
  da.email AS agent_email,
  dd.department,
  dd.front_or_back,
  dt.motivation AS contact_motivation_tag,
  dt.theme_detail AS contact_theme_detail_tag,
  dt.customer_type_tag AS customer_type_tag,
  dtt.tags AS tag,
  dt.step_tag AS step_tag,
  dd.team,
  dd.journey_step,
  dd.area,
  bmt.sla_target,
  bmt.days_worked,
  bmt.days_worked_with_days_offs,
  bmt.days_off,
  bmt.is_daily_backlog,
  bmt.is_backlog_within_sla AS is_backlog_in_time,
  bmt.is_backlog_with_exceed_sla AS is_backlog_not_in_time,
  bmt.dt_metric_reference,
  bmt.ts_started,
  bmt.ts_solved,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day
FROM
  dw_customer_support.fact_backlog_metrics_tasks AS bmt
LEFT JOIN
  dw_customer_support.dim_taxonomy AS dt
    ON bmt.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN
  dw_customer_support.dim_ticket_tags AS dtt
    ON bmt.sk_tags = dtt.sk_tags
LEFT JOIN
  dw_customer_support.dim_department AS dd
    ON bmt.sk_main_department = dd.sk_department
LEFT JOIN
  dw_customer_support.dim_agent AS da
    ON bmt.sk_agent = da.sk_agent
WHERE
  DATE(bmt.dt_metric_reference) >= '2022-07-19'
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
    'Reparos Urgentes [Back]',
    'Reparos Back [ATN]',
    'Triagem Reparos [Back]',
    'PARTNERS/CIQ [FRONT] [PRE]',
    'Reparos Comuns [Back]',
    'Assessor de Proprietário [ASP] [PRE] [BACK]'
  )
