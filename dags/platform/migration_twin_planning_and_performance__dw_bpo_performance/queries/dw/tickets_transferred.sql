WITH contacts_vol AS (
  -- Calcula volume de interações para definir erro humano (Regra: > 2 interações)
  SELECT
    sk_contact,
    COUNT(sk_interaction) AS vol_interaction
  FROM dw_customer_support.fact_customer_contacts
  WHERE date(ts_task_created) >= date('2024-01-01')
  GROUP BY 1
),


segments_raw AS (
  SELECT DISTINCT
    fcc.sk_ticket,
    fcc.sk_task AS sk_segment,
    fcc.sk_interaction, -- Chave fundamental
    fcc.sk_contact,
   
    -- Dimensões Básicas
    da.email AS agent_email,
    da.agent_organization AS organization,
    dd.team,
    dd.department,
   
    -- Dimensões de BI (Filtros)
    dd.area,
    dd.front_or_back,
   
    -- Temas e Taxonomia
    dt.theme,
    dt.theme_detail,


    -- Dados de Origem e Canal
    fcc.channel,
    CASE
      WHEN fcc.origin = 'chat in app' THEN 'chat5a'
      ELSE 'whatsapp'
    END AS ticket_origin,


    -- Métricas de Tempo e SLA
    fcc.first_reply_time, -- O campo original está aqui
    (fcc.ts_task_created - interval '3' hour) AS ts_started,
   
    -- Status e Flags
    UPPER(fcc.status) AS status,
    fcc.is_interaction_answered,
    fcc.is_contact_answered as is_answered,
    fcc.is_last_interaction,
    fcc.is_first_department_interaction,
   
    -- Dados de Transferência
    dd2.department AS transferred_to_raw,
    dd2.team AS transferred_to_team,
   
    dd_first.department AS first_department,
   
    -- Last Department vindo da FACT TICKETS (Correção Mai/25)
    dd_last.department AS last_department_raw,


    -- Volume de interações
    cv.vol_interaction,


    -- Flags de Status simples
    CASE WHEN fcc.status = 'idled' THEN 1 ELSE 0 END AS task_idled,
    CASE WHEN fcc.status = 'expired' THEN 1 ELSE 0 END AS session_expired


  FROM
    dw_customer_support.fact_customer_contacts AS fcc
 
  -- Joins
  LEFT JOIN
    dw_customer_support.fact_tickets AS ft
      ON ft.sk_ticket = fcc.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON dd.sk_department = fcc.sk_department
  LEFT JOIN
    dw_customer_support.dim_department AS dd2
      ON dd2.sk_department = fcc.sk_next_department
  LEFT JOIN
    dw_customer_support.dim_department AS dd_first
      ON dd_first.sk_department = fcc.sk_first_department
  LEFT JOIN
    dw_customer_support.dim_department AS dd_last
      ON dd_last.sk_department = ft.sk_main_department
  LEFT JOIN
    dw_customer_support.dim_analyst as da
      ON fcc.sk_analyst = da.sk_analyst
  LEFT JOIN
    dw_customer_support.dim_ticket AS dit
      ON dit.sk_ticket = fcc.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dit.sk_taxonomy = dt.sk_taxonomy
  LEFT JOIN
    contacts_vol cv
      ON fcc.sk_contact = cv.sk_contact


  WHERE
    fcc.channel IN ('chat', 'call')
    AND fcc.origin NOT IN ('outbound')
    AND fcc.direction = 'inbound'
    AND dd.front_or_back = 'front'
    AND dd.area = 'CX'
    AND dd.team IN ('Moving', 'Payments', 'Repairs/Ongoing Front', 'Offboarding Front', 'Visits','Propostas','CX Partners','CX Compra e Venda','CIQ')
),


segments_normalized AS (
  SELECT
    *,
    -- Limpeza dos nomes de departamento para comparação e classificação
    TRIM(REPLACE(department, '[AeC] ', '')) AS clean_department,
    TRIM(REPLACE(last_department_raw, '[AeC] ', '')) AS clean_last_department
  FROM segments_raw
)


SELECT
  -- IDs
  sk_ticket,
  sk_contact,
  sk_segment,
  sk_interaction,
 
  -- Agente
  agent_email,
  organization,
 
  -- Departamento e Time
  team,
  department,
  area,
  front_or_back,


  -- Detalhes
  ticket_origin,
  status,
  theme,
  theme_detail,
  channel,
 
  -- Jornada da Transferência
  first_department,
  last_department_raw AS last_department,
  transferred_to_raw AS transferred_to,
  is_first_department_interaction,
  transferred_to_team,
 
  -- CORREÇÃO AQUI: Alias correto para o campo de tempo
  first_reply_time AS first_response_time,


  -- Flags de Controle
  task_idled,
  session_expired,
  is_last_interaction,
  is_answered,
  is_interaction_answered,
 
  -- COLUNA CALCULADA: Transfer Reason (Lógica Ajustada: Bruto vs Limpo)
  CASE
    WHEN status = 'TRANSFERRED'
      AND (transferred_to_raw != clean_last_department AND vol_interaction > 2) THEN 'human_error'
    WHEN status = 'TRANSFERRED' then 'bot_error'
    ELSE 'no_transfer'
  END AS transfer_reason,


  -- COLUNA CALCULADA: Pre vs Post Contract
  CASE when clean_department in (
      'CX Partners Tarefas [PRE] [BACK]',
      'CX Propostas Tarefas [PRE] [BACK]',
      'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
      'FUP Carteirização B2C [CLO] [PRE] [BACK]',
      'EARLY DEMAND [CLOSING] [BACK]',
      'Closing PP Multi [CLO] [PRE] [BACK]',
      'CX Parceiros Compra e Venda [FRONT]',
      'CX Parceiros [FRONT] [PRE]',
      'CX Parceiros da Portaria [FRONT] [PRE]',
      'CX Propostas [FRONT] [PRE]',
      'CX Visitas [FRONT] [PRE]',
      'Consultores imobiliários 5A',
      '[WH] Credito [FRONT]',
      '[WH] Closing [FRONT]'
    ) THEN 'pre_rental'
    WHEN clean_department in (
      'CX Mudança [FRONT] [POS]',
      'CX Pagamentos [FRONT] [POS]',
      'CX Reparos [FRONT] [POS]',
      'CX Rescisão [FRONT] [POS]',
      'Aditivos [REP] [POS] [BACK]',
      'Entrada no imóvel [ONB] [POS] [BACK]',
      'CX Pagamentos Ativo [POS] [BACK] [PAY]',
      'Alteração de dados bancários [BACK]',
      'Atendimento Escalado [OFF] [POS] [BACK]'
    ) THEN 'post-rental'
    WHEN clean_department IN ('Notificação Extrajudicial [CE] [POS] [BACK]', 'CX Conta Comigo [POS] [BACK]', 'Dados Bancários [CE] [POS] [BACK]', 'Casos Especiais [CE] [POS] [BACK]', 'Midias Ops [POS] [BACK]') then 'CSI'
    ELSE 'others'
  END AS pre_and_post_contract,


  -- METRICAS CALCULADAS (Flags 1/0 para agregação posterior)
 
  -- 1. Transferências Válidas
  CASE
    WHEN status = 'TRANSFERRED'
     AND is_first_department_interaction = TRUE
     AND COALESCE(transferred_to_team, '') <> 'Inside Sales'
     AND is_interaction_answered = TRUE
    THEN 1
    ELSE 0
  END AS task_transferred,


  -- 2. SLA (Chat 90s, Call 60s)
  CASE
    WHEN channel = 'chat' AND first_reply_time <= 90 THEN 1
    WHEN channel = 'call' AND first_reply_time <= 60 THEN 1
    ELSE 0
  END AS is_in_sla,


  -- 3. Volume de Tickets Chat
  CASE
    WHEN channel = 'chat' THEN 1 ELSE 0
  END AS is_ticket_chat,
 
  -- 4. Abandonos de Call
  CASE
    WHEN channel = 'call' AND is_answered = FALSE THEN 1 ELSE 0
  END AS is_call_abandoned,


  ts_started,
 
  -- Particionamento
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day,
  NOW() AS ts_load


FROM
  segments_normalized



