WITH ticket_perspective AS (
  SELECT
    ft.sk_ticket,
    ft.sk_user,
    COALESCE(ft.sk_user,ft.sk_contract) AS sk_user_contract,
    ft.channel,
    ft.front_or_back,
    dd.department AS department,
    dd.board,
    dd.team AS team,
    dd.area AS area,
    dt.customer_type_tag AS customer_type,
    dt.journey,
    dd.journey_step,
    CASE
      WHEN ft.ticket_origin = 'call inapp' THEN 'INBOUND'
      WHEN ft.ticket_origin = 'call inbound' THEN 'INBOUND'
      WHEN ft.ticket_origin = 'chat5a' THEN 'INBOUND'
      WHEN ft.ticket_origin = 'call outbound' THEN 'OUTBOUND'
      ELSE UPPER(ft.direction)
    END AS refined_direction,
    CASE
      WHEN dd.team IN 
        (
          'Repairs/Ongoing Front',
          'Repairs/Ongoing Back',
          'Ongoing Back',
          'Ong Back'
        )
      THEN 'Reparos'
      WHEN dd.team IN (
        'Rental Manager',
        'Rental Manager Gold',
        'Rental Manager CTL')
      THEN 'Rental Manager'
      WHEN dd.team IN 
        (
          'Payments',
          'Payments Ativo Back'
        )
      THEN 'Payments'
      WHEN dd.team IN 
        (
          'CX Partners',
          'CX Compra e Venda',
          'CX Partners For Sale'
          )
      THEN 'Partners'
      WHEN dd.team IN 
        (
          'Onboarding Back',
          'Moving'
        )
      THEN 'Onboarding'
      WHEN dd.team IN 
        (
          'Offboarding Front',
          'Offboarding Back'
        )
      THEN 'Offboarding'
      WHEN dd.team IN (
        'ReclameAqui',
        'Privacy',
        'Casos Especiais',
        'PROCON',
        'Dados Bancários',
        'Conta Comigo',
        'Subsídios',
        'Consumidor.Gov',
        'Notificação Extrajudicial',
        'Midias Ops',
        'ReclameAqui - Grupo5A',
        'Reversão de NPS')
      THEN 'CSI'
      ELSE dd.team
    END AS team_adjusted,
    ft.replies,
    ft.reopens,
    ft.ts_created AS ts_started
  FROM
    dw_customer_support.fact_tickets AS ft
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON dd.sk_department = ft.sk_main_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = ft.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_ticket AS dit
      ON CAST(dit.sk_ticket AS STRING) = ft.sk_ticket
  WHERE
    ft.sk_ticket IS NOT NULL
    AND ft.ts_created >= CAST('2023-01-01' AS DATE)
    AND dd.area NOT LIKE ('%MX%')
)
,recontact AS (
  SELECT
    sk_ticket,
    CASE
      WHEN
        DATE_DIFF(DAY, DATE(ts_started), LEAD(DATE(ts_started)) OVER(PARTITION BY sk_user, team ORDER BY ts_started)) <= 4
        AND sk_ticket != LEAD(sk_ticket) OVER(PARTITION BY sk_user_contract, team ORDER BY ts_started)
      THEN 1
      ELSE 0
    END AS recontact_flag
  FROM
    ticket_perspective
  WHERE
    sk_user_contract > 0
    AND area = 'CX'
    AND (front_or_back = 'front'
      OR department IN ('[WH] Credito [FRONT]', '[WH] Closing [FRONT]'))
    AND (refined_direction = 'INBOUND'
      AND channel IN ('call', 'chat','whatsapp'))
    AND department NOT IN ('Welcome Onboarding [BACK] [POS]', 'CX Welcome Onboarding [FRONT][POS]' )
)
, back_penalizations AS (
  SELECT
    CASE
      WHEN channel IN ('whatsapp') THEN 1 ELSE 0
    END AS flag_back_wpp,
    CASE
      WHEN
        refined_direction NOT IN ('INBOUND')
        AND front_or_back = 'back'
      THEN 1
      ELSE 0
    END AS flag_back_outbound,
    CASE
      WHEN (
        (replies >= 1
          OR reopens > 0)
          AND front_or_back = 'back')
      THEN 1
      ELSE 0
    END AS flag_replies,
    CASE
      WHEN front_or_back = 'back' THEN 1
      ELSE 0
    END AS flag_back,
    sk_user_contract,
    team_adjusted,
    ts_started
  FROM
    ticket_perspective
  WHERE
    area = 'CX'
    AND (front_or_back = 'back'
      OR channel = 'whatsapp')
    AND department NOT IN ('Welcome Onboarding [BACK] [POS]', 'CX Welcome Onboarding [FRONT][POS]' )
    AND (sk_user_contract IS NOT NULL
      OR sk_user_contract > 0)
)
,base AS (
  SELECT
    tp.sk_ticket,
    tp.channel,
    tp.journey,
    tp.journey_step,
    tp.department,
    tp.board,
    tp.team,
    tp.area,
    tp.refined_direction,
    tp.customer_type,
    r.recontact_flag,
    bpe.flag_back_outbound,
    bpe.flag_back_wpp,
    bpe.flag_back,
    bpe.flag_replies,
    DATE(tp.ts_started) AS dt_ticket_created
  FROM
    ticket_perspective AS tp
  LEFT JOIN
    recontact AS r
      ON r.sk_ticket = tp.sk_ticket
  LEFT JOIN
    back_penalizations AS bpe
      ON tp.sk_user_contract = bpe.sk_user_contract
      AND tp.team_adjusted = bpe.team_adjusted
      AND tp.ts_started <= bpe.ts_started
      AND DATE_DIFF(DAY, DATE(tp.ts_started), DATE(bpe.ts_started)) <= 4
  WHERE
    tp.front_or_back = 'front'
    AND tp.sk_user_contract IS NOT NULL
    AND tp.sk_user_contract > 0
    AND tp.department IN
      (
        'CX Mudança [FRONT] [POS]',
        'CX Parceiros Compra e Venda [FRONT]',
        'CX Parceiros [FRONT] [PRE]',
        'CX Parceiros da Portaria [FRONT] [PRE]',
        'CX Propostas [FRONT] [PRE]',
        'CX Visitas [FRONT] [PRE]',
        'Consultores imobiliários 5A',
        'CX Pagamentos [FRONT] [POS]',
        'CX Reparos [FRONT] [POS]',
        'CX Rescisão [FRONT] [POS]',
        'CX Visitas N1 & N2 [VIS] [PRE] [FRONT] [OUT]',
        'CX PROPOSTAS CALL/CHAT [PRO][PRE][FRONT]',
        'Consultores imobiliários 5A',
        'CX Plaquinhas [FRONT] [PRE]',
        'CX Entrada no imóvel [ONB] [POS] [FRONT]',
        'CX Pagamentos N1 [PAY] [POS] [FRONT]',
        'CX Durante a locação e reparos [POS] [FRONT]',
        'CX Rescisão e Vistoria [OFF] [POS] [FRONT]',
        '[WH] Credito [FRONT]',
        '[WH] Closing [FRONT]'
      )
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY bpe.sk_user_contract, tp.sk_ticket ORDER BY bpe.ts_started ASC) = 1
)
SELECT
  channel,
  journey,
  journey_step,
  board,
  department,
  team,
  area,
  customer_type,
  COUNT(DISTINCT
    CASE
      WHEN (recontact_flag = 1
      OR flag_back_outbound = 1
      OR flag_back_wpp = 1
      OR flag_back = 1) THEN NULL
      ELSE sk_ticket
    END)
  AS amount_resolutions,
  CAST(COUNT(DISTINCT sk_ticket) AS DOUBLE) AS amount_tickets,
  COUNT(DISTINCT
    CASE
      WHEN (recontact_flag = 1
      OR flag_back_outbound = 1
      OR flag_back_wpp = 1
      OR flag_back = 1) THEN NULL
      ELSE sk_ticket
    END)
    /CAST(COUNT(DISTINCT sk_ticket) AS DOUBLE) AS fcr_rate,
  dt_ticket_created
FROM
  base
WHERE
  dt_ticket_created <= CURRENT_DATE - 5
  AND refined_direction = 'INBOUND'
GROUP BY
  ALL
