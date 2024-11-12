WITH tickets_perspective AS (
  SELECT DISTINCT
    ft.sk_ticket,
    ft.sk_user,
    CASE
      WHEN ft.channel IN ('chat','call') THEN ft.channel
      WHEN dit.ticket_via = 'whatsapp' THEN 'whatsapp'
      ELSE ft.channel
    END AS channel,
    dt.journey,
    dd_last.journey_step,
    dd_last.board,
    dd_last.department,
    dd_last.team,
    dd_last.area,
    dt.customer_type_tag AS customer_type,
    dit.tags,
    dmt.origin,
    ROW_NUMBER() OVER(
      PARTITION BY dmt.sk_task
      ORDER BY CAST(dmt.sla_target AS INTEGER) DESC
    ) AS row_num,
    ft.ts_started
  FROM
    dw_customer_support.fact_ticket AS ft
  LEFT JOIN
    dw_customer_support.dim_department AS dd_last
      ON dd_last.sk_department = ft.sk_main_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = ft.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_ticket AS dit
      ON dit.sk_ticket = ft.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_channel AS dc
      ON dc.sk_channel = ft.sk_channel
  LEFT JOIN
    dw_customer_support.fact_demand_metrics_tasks AS dmt
      ON dmt.sk_task = CAST(ft.sk_ticket AS STRING)
  WHERE
    ft.ts_started >= CAST('2021-01-01' AS DATE)
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
        AND origin NOT IN ('whatsapp')
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
        AND origin != 'whatsapp'
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
        AND origin != 'whatsapp'
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
        AND origin != 'whatsapp'
      THEN sk_ticket
      ELSE NULL
    END) * 1.0000),0)
  AS escalation_rate,
  DATE(tp.ts_started) AS dt_ticket_created
FROM
  tickets_perspective AS tp
WHERE
  tp.row_num = 1
GROUP BY
  ALL
