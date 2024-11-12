WITH ticket_perspective AS (
  SELECT
    ft.sk_ticket,
    ft.sk_user,
    COALESCE(ft.sk_user,ft.sk_contract) AS sk_user_contract,
    CASE
      WHEN ft.channel IN ('chat','call') THEN ft.channel
      WHEN dit.ticket_via = 'whatsapp'
      THEN 'whatsapp'
      ELSE ft.channel
    END AS channel,
    ft.front_or_back,
    dd.department AS department,
    dd.board,
    dd.team AS team,
    dd.area AS area,
    dt.customer_type_tag AS customer_type,
    dt.journey,
    dd.journey_step,
    CASE
      WHEN ft.ticket_origin = 'call inapp' THEN UPPER(dc.direction)
      WHEN dit.ticket_via = 'whatsapp' THEN 'OUTBOUND'
      WHEN ft.ticket_origin = 'call inbound' THEN 'INBOUND'
      WHEN ft.ticket_origin = 'chat5a' THEN 'INBOUND'
      WHEN ft.ticket_origin = 'call outbound' THEN 'OUTBOUND'
      WHEN dit.ticket_via = 'whatsapp' then UPPER(dc.direction)
      ELSE UPPER(dc.direction)
    END AS refined_direction,
    CASE
      WHEN dd.team IN (
        'Repairs/Ongoing Front',
        'Repairs/Ongoing Back')
      THEN 'Reparos'
      WHEN dd.team IN (
        'Rental Manager',
        'Rental Manager Gold',
        'Rental Manager',
        'Rental Manager Gold',
        'Rental Manager CTL')
      THEN 'Rental Manager'
      WHEN dd.team IN (
        'Payments',
        'Payments Ativo Back',
        'Payments Ativo Back')
      THEN 'Payments'
      WHEN dd.team IN (
        'CX Partners',
        'CX Compra e Venda',
        'CX Partners For Sale')
      THEN 'Partners'
      WHEN dd.team IN (
        'Ongoing Back',
        'Ongoing Back',
        'Ong Back')
      THEN 'Ongoing'
      WHEN dd.team IN (
        'Onboarding Back',
        'Onboarding Back',
        'Moving')
      THEN 'Onboarding'
      WHEN dd.team IN (
        'Offboarding Front',
        'Offboarding Back',
        'Offboarding Back')
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
    ft.ts_started
  FROM
    dw_customer_support.fact_ticket AS ft
  LEFT JOIN
    dw_customer_support.dim_department AS dd
      ON dd.sk_department = ft.sk_main_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = ft.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_channel AS dc
      ON dc.sk_channel = ft.sk_channel
  LEFT JOIN
    dw_customer_support.dim_ticket AS dit
      ON CAST(dit.sk_ticket AS STRING) = ft.sk_ticket
  WHERE
    ft.sk_ticket IS NOT NULL
    AND ft.ts_started >= CAST('2023-01-01' AS DATE)
    AND dd.area NOT LIKE ('%MX%')
)
,recontact AS (
  SELECT
    sk_ticket,
    CASE
      WHEN DATEDIFF(LEAD(DATE(ts_started)) OVER(PARTITION BY sk_user, team ORDER BY ts_started), DATE(ts_started)) <= 4 THEN 1
      ELSE 0
    END AS recontact_flag
  FROM
    ticket_perspective
  WHERE
    channel IN ('call', 'chat','whatsapp','email')
    AND sk_user IS NOT NULL
    AND area = 'CX'
    AND front_or_back = 'front'
)
, back_penalizations AS (
  SELECT
    CASE
      WHEN channel IN ('whatsapp') THEN 1 ELSE 0
    END AS flag_back_wpp,
    CASE
      WHEN refined_direction NOT IN ('INBOUND')THEN 1
      WHEN
        front_or_back = 'back'
        AND channel = 'call'
      THEN 1
      ELSE 0
    END AS flag_back_outbound,
    CASE
      WHEN replies >= 1 THEN 1 ELSE 0
    END AS flag_replies,
    sk_user_contract,
    team_adjusted,
    ts_started
  FROM
    ticket_perspective
  WHERE
    area = 'CX'
    AND (
      channel IN ('whatsapp')
      OR refined_direction NOT IN ('INBOUND')
      OR (front_or_back = 'back'
        AND channel = 'call')
      OR replies >= 1)
    AND sk_user_contract IS NOT NULL
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
      AND DATEDIFF(DATE(bpe.ts_started), DATE(tp.ts_started)) <= 4
  WHERE
    tp.front_or_back = 'front'
    AND tp.sk_user IS NOT NULL
    AND tp.department IN (
      'CX Mudança [FRONT] [POS]',
      'CX Parceiros Compra e Venda [FRONT]',
      'CX Parceiros [FRONT] [PRE]',
      'CX Parceiros da Portaria [FRONT] [PRE]',
      'CX Propostas [FRONT] [PRE]',
      'CX Visitas [FRONT] [PRE]',
      'Consultores imobiliários 5A',
      'CX Pagamentos [FRONT] [POS]',
      'CX Reparos [FRONT] [POS]',
      'CX Rescisão [FRONT] [POS]')
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY tp.sk_ticket ORDER BY CAST(bpe.ts_started AS timestamp) ASC) = 1
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
      OR flag_replies = 1) THEN NULL
      ELSE sk_ticket
    END)
  AS amount_resolutions,
  CAST(COUNT(DISTINCT sk_ticket) AS DOUBLE) AS amount_tickets,
  COUNT(DISTINCT
    CASE
      WHEN (recontact_flag = 1
      OR flag_back_outbound = 1
      OR flag_back_wpp = 1
      OR flag_replies = 1) THEN NULL
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
