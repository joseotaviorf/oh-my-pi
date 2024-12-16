WITH tickets_perspective AS (
  SELECT DISTINCT
    ft.sk_ticket,
    ft.sk_user,
    ft.channel,
    dt.journey,
    dd_last.journey_step,
    dd_last.board,
    dd_last.department,
    dd_last.team,
    dd_last.area,
    dt.customer_type_tag AS customer_type,
    dit.tags,
    'email' AS origin,
    ft.ts_created AS ts_started
  FROM
    dw_customer_support.fact_tickets AS ft
  LEFT JOIN
    dw_customer_support.dim_department AS dd_last
      ON dd_last.sk_department = ft.sk_main_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = ft.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_ticket AS dit
      ON dit.sk_ticket = ft.sk_ticket
  WHERE
    ft.ts_created >= CAST('2021-01-01' AS DATE)
    AND ft.channel = 'email'
)
SELECT
  tp.channel,
  tp.journey,
  tp.journey_step,
  tp.board,
  tp.department,
  tp.team,
  tp.area,
  tp.customer_type,
  COUNT(DISTINCT
    CASE
      WHEN department IN (
        '[MX] Midia OPS'
        ,'CX Conta Comigo [POS] [BACK]'
        ,'CX ReclameAqui Adquiridas [CE] [POS] [BACK]'
        ,'Midias Ops [POS] [BACK]'
        ,'Notificação Extrajudicial [CE] [POS] [BACK]'
        ,'Ouvidoria [CE] [POS] [BACK]'
        ,'Ouvidoria For Sale [CE] [SALE] [BACK]'
        ,'PROCON [CE] [POS] [BACK]'
        ,'ReclameAqui [CE] [POS] [BACK]')
        AND tags NOT LIKE '%api_reclame_aqui%'
      THEN sk_ticket
      ELSE NULL END)
  AS amount_escalation,
  (COUNT(DISTINCT
    CASE
      WHEN department IN (
        'CX Partners Tarefas [PRE] [BACK]'
        ,'CX Propostas Tarefas [PRE] [BACK]'
        ,'Aditivos [REP] [POS] [BACK]'
        ,'Entrada no imóvel [ONB] [POS] [BACK]'
        ,'CX Pagamentos Ativo [POS] [BACK] [PAY]'
        ,'Alteração de dados bancários [BACK]'
        ,'Triagem Reparos [Back]'
        ,'Rescisão por Inadimplência [OFF][POS][BACK]'
        ,'Atendimento Escalado [OFF] [POS] [BACK]'
        ,'Reparos Comuns [Back]'
        ,'Offboarding Reparos [OFF] [POS] [BACK]'
        ,'Proteção QuintoAndar [OFF] [POS] [BACK]'
        ,'Reparos [BACK]'
        ,'Autosserviço Reparos [BACK]')
      THEN sk_ticket
      ELSE NULL
    END) * 1.0000)
  AS amount_escalation_responses,
  COUNT(DISTINCT
    CASE
      WHEN department IN (
        '[MX] Midia OPS'
        ,'CX Conta Comigo [POS] [BACK]'
        ,'CX ReclameAqui Adquiridas [CE] [POS] [BACK]'
        ,'Midias Ops [POS] [BACK]'
        ,'Notificação Extrajudicial [CE] [POS] [BACK]'
        ,'Ouvidoria [CE] [POS] [BACK]'
        ,'Ouvidoria For Sale [CE] [SALE] [BACK]'
        ,'PROCON [CE] [POS] [BACK]'
        ,'ReclameAqui [CE] [POS] [BACK]')
        AND tags NOT LIKE '%api_reclame_aqui%'
      THEN sk_ticket
      ELSE NULL END)
  /NULLIF((COUNT(DISTINCT
    CASE
      WHEN department IN (
        'CX Partners Tarefas [PRE] [BACK]'
        ,'CX Propostas Tarefas [PRE] [BACK]'
        ,'Aditivos [REP] [POS] [BACK]'
        ,'Entrada no imóvel [ONB] [POS] [BACK]'
        ,'CX Pagamentos Ativo [POS] [BACK] [PAY]'
        ,'Alteração de dados bancários [BACK]'
        ,'Triagem Reparos [Back]'
        ,'Rescisão por Inadimplência [OFF][POS][BACK]'
        ,'Atendimento Escalado [OFF] [POS] [BACK]'
        ,'Reparos Comuns [Back]'
        ,'Offboarding Reparos [OFF] [POS] [BACK]'
        ,'Proteção QuintoAndar [OFF] [POS] [BACK]'
        ,'Reparos [BACK]'
        ,'Autosserviço Reparos [BACK]')
      THEN sk_ticket
      ELSE NULL
    END) * 1.0000),0)
  AS escalation_rate,
  DATE(tp.ts_started) AS dt_ticket_created
FROM
  tickets_perspective AS tp
GROUP BY ALL
