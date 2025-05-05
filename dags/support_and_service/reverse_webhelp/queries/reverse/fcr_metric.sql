WITH tickets_perspective AS (
  SELECT
    ft.sk_ticket,
    ft.sk_contract,
    ft.sk_user,
    COALESCE(ft.sk_user,ft.sk_contract) AS sk_user_contract,
    ft.sk_session,
    ft.channel,
    ft.replies,
    ft.reopens,
    ft.front_or_back,
    ft.ts_created AS ts_started,
    ft.ts_closed,
    ft.ts_solved,
    dd_last.department AS last_department,
    CASE
      WHEN dd_last.department IN ('CX Reparos [FRONT] [POS]')
        AND dt.theme IN ('ongoing_rental_house_repairs_and_improvements') THEN 'Reparos'
      WHEN dd_last.department IN ('CX Reparos [FRONT] [POS]') THEN 'Ongoing'
      ELSE dd_last.team
    END AS last_team,
    dd_last.area AS last_area,
    dt.theme,
    dt.theme_detail,
    CASE
        WHEN ft.ticket_origin = 'call inapp' THEN 'INBOUND'
        WHEN ft.ticket_origin = 'call inbound' THEN 'INBOUND'
        WHEN ft.ticket_origin = 'chat5a' THEN 'INBOUND'
        WHEN ft.ticket_origin = 'call outbound' THEN 'OUTBOUND'
        ELSE UPPER(ft.direction)
    END AS refined_direction,
    da_last.sk_analyst AS sk_last_analyst,
    da_last.email AS last_agent_email,
    da_last.full_name AS last_agent_full_name,
    da_last.agent_organization AS last_agent_organization,
    CASE
      WHEN dd_last.department IN ('CX Reparos [FRONT] [POS]')
        AND dt.theme IN ('ongoing_rental_house_repairs_and_improvements') THEN 'Reparos'
      WHEN dd_last.department IN ('CX Reparos [FRONT] [POS]') THEN 'Ongoing'
      WHEN dd_last.team IN ('Repairs/Ongoing Front', 'Repairs/Ongoing Back') THEN 'Reparos'
      WHEN dd_last.team IN ('Ongoing Back', 'Ongoing Back', 'Ong Back') THEN 'Ongoing'
      WHEN dd_last.team IN ('Rental Manager', 'Rental Manager Gold', 'Rental Manager CTL') THEN 'Rental Manager'
      WHEN dd_last.team IN ('Payments', 'Payments Ativo Back') THEN 'Payments'
      WHEN dd_last.team IN ('CX Partners', 'CX Compra e Venda', 'CX Partners For Sale') THEN 'Partners'
      WHEN dd_last.team IN ('Onboarding Back', 'Moving') THEN 'Onboarding'
      WHEN dd_last.team IN ('Offboarding Front', 'Offboarding Back') THEN 'Offboarding'
      WHEN dd_last.team IN (
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
        'Reversão de NPS'
      ) THEN 'CSI'
      ELSE dd_last.team
    END AS team_adjusted
  FROM
    dw_customer_support.fact_tickets AS ft
  LEFT JOIN
    dw_customer_support.dim_department AS dd_last
      ON dd_last.sk_department = ft.sk_main_department
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dt
      ON dt.sk_taxonomy = ft.sk_taxonomy
  LEFT JOIN
    dw_customer_support.dim_analyst AS da_last
      ON da_last.sk_analyst = ft.sk_last_analyst
  WHERE
    ft.sk_ticket IS NOT NULL
    AND ft.ts_created >= DATE('{load_start_date}') - INTERVAL 1 YEAR
    AND dd_last.area NOT LIKE ('%MX%')
),
recontact_drilldown AS (
  SELECT
    tp.sk_ticket,
    CASE
      WHEN DATE_DIFF(DAY, DATE(tp.ts_started), LEAD(DATE(tp.ts_started)) OVER(PARTITION BY tp.sk_user, tp.last_team ORDER BY tp.ts_started)) <= 4 THEN
        CASE WHEN tp.sk_ticket != LEAD(tp.sk_ticket) OVER(PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) THEN 1 ELSE 0 END
      ELSE 0
    END AS recontact_flag,
    CASE
      WHEN DATE_DIFF(DAY, DATE(tp.ts_started), LEAD(DATE(tp.ts_started)) OVER(PARTITION BY tp.sk_user, tp.last_team, tp.theme ORDER BY tp.ts_started)) <= 4 THEN
        CASE WHEN tp.sk_ticket != LEAD(tp.sk_ticket) OVER(PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started)
                  AND tp.theme IS NOT NULL THEN 1 ELSE 0 END
      ELSE 0
    END AS theme_recontact_flag,
    CASE
      WHEN DATE_DIFF(DAY, DATE(tp.ts_started), LEAD(DATE(tp.ts_started)) OVER(PARTITION BY tp.sk_user, tp.last_team, tp.theme, tp.theme_detail ORDER BY tp.ts_started)) <= 4 THEN
        CASE WHEN tp.sk_ticket != LEAD(tp.sk_ticket) OVER(PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme, tp.theme_detail ORDER BY tp.ts_started)
                  AND tp.theme IS NOT NULL AND tp.theme_detail IS NOT NULL THEN 1 ELSE 0 END
      ELSE 0
    END AS theme_detail_recontact_flag,
    LEAD(tp.sk_ticket) OVER(PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS next_contact_sk_ticket,
    LEAD(tp.ts_started) OVER(PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS next_contact_ts_started,
    LEAD(tp.last_agent_email) OVER(PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS next_agent,
    LEAD(tp.channel) OVER(PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS next_contact_channel,
    LEAD(tp.theme) OVER(PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS next_contact_theme,
    LEAD(tp.theme_detail) OVER(PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS next_contact_theme_detail,
    LEAD(tp.sk_ticket) OVER(PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started) AS next_contact_per_theme_sk_ticket,
    LEAD(tp.sk_ticket) OVER(PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme, tp.theme_detail ORDER BY tp.ts_started) AS next_contact_per_theme_detail_sk_ticket
  FROM
    tickets_perspective AS tp
  WHERE
    1=1
    and tp.sk_user_contract > 0
    AND tp.last_area = 'CX'
    AND (tp.front_or_back = 'front' or last_department in ('[WH] Credito [FRONT]',  '[WH] Closing [FRONT]'))
    AND last_department not in ('Welcome Onboarding [BACK] [POS]','CX Welcome Onboarding [FRONT][POS]',
    'EARLY DEMAND [CLOSING] [BACK]','FUP Carteirização B2C [CLO] [PRE] [BACK]','Closing Contratos [CLO] [PRE] [BACK]')
    AND (
      tp.refined_direction = 'INBOUND'
      AND tp.channel IN ('chat', 'call', 'whatsapp')
    )
),
back_penalizations AS (
  SELECT
    tp.sk_user_contract,
    tp.sk_ticket,
    tp.channel,
    tp.team_adjusted,
    tp.ts_started,
    tp.theme,
    CASE
      WHEN tp.front_or_back = 'back' THEN 1
      ELSE 0
    END AS flag_back
  FROM
    tickets_perspective AS tp
  WHERE
    1=1
    AND tp.sk_user_contract > 0
    AND tp.last_area = 'CX'
    AND (tp.front_or_back = 'back' OR tp.channel = 'whatsapp')
    AND last_department not in ('Welcome Onboarding [BACK] [POS]','CX Welcome Onboarding [FRONT][POS]'
        ,'EARLY DEMAND [CLOSING] [BACK]','FUP Carteirização B2C [CLO] [PRE] [BACK]','Closing Contratos [CLO] [PRE] [BACK]')
    AND tp.sk_user_contract IS NOT NULL
    AND tp.sk_user_contract > 0
),
fcr AS (
  SELECT DISTINCT
    tp.sk_ticket,
    tp.sk_user_contract,
    tp.sk_session,
    tp.channel,
    tp.front_or_back,
    tp.ts_started,
    tp.ts_closed,
    tp.ts_solved,
    tp.last_department,
    tp.last_team,
    tp.last_area,
    tp.theme,
    tp.theme_detail,
    tp.refined_direction,
    tp.sk_last_analyst,
    tp.last_agent_email,
    tp.last_agent_full_name,
    tp.last_agent_organization,
    tp.team_adjusted,
    rd.recontact_flag,
    rd.theme_recontact_flag,
    rd.theme_detail_recontact_flag,
    rd.next_contact_sk_ticket,
    rd.next_contact_channel,
    rd.next_agent,
    rd.next_contact_ts_started,
    rd.next_contact_theme,
    rd.next_contact_theme_detail,
    rd.next_contact_per_theme_sk_ticket,
    rd.next_contact_per_theme_detail_sk_ticket,
    bpe.flag_back,
    bpe.sk_ticket AS sk_ticket_penalized,
    bpe.ts_started AS ts_started_penalized,
    bpe.channel AS channel_penalized,
    bpe.theme AS theme_penalized,
    CASE
      WHEN bpe.sk_user_contract IS NULL THEN 1
      ELSE ROW_NUMBER() OVER(PARTITION BY tp.sk_ticket ORDER BY CAST(bpe.ts_started AS TIMESTAMP) ASC)
    END AS rank_cte
  FROM
    tickets_perspective AS tp
  LEFT JOIN
    recontact_drilldown AS rd
      ON rd.sk_ticket = tp.sk_ticket
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
    AND tp.last_department IN (
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
      '[WH] Credito [FRONT]',  '[WH] Closing [FRONT]'
    )
)
SELECT DISTINCT
  sk_ticket,
  sk_last_analyst AS sk_agent,
  sk_session AS sk_main_session,
  channel,
  last_department AS main_department,
  refined_direction AS direction,
  last_area AS area,
  front_or_back,
  last_team AS team,
  theme AS contact_theme_tag,
  theme_detail AS contact_theme_detail_tag,
  CONCAT('https://quintoandar.zendesk.com/agent/tickets/', sk_ticket) AS external_url,
  last_agent_full_name AS agent_full_name,
  last_agent_email AS agent_email,
  last_agent_organization AS agent_company,
  ts_started,
  ts_solved,
  ts_closed,
  recontact_flag,
  theme_recontact_flag,
  theme_detail_recontact_flag,
  next_contact_sk_ticket,
  next_contact_channel,
  next_contact_ts_started,
  next_contact_theme,
  next_contact_theme_detail,
  next_contact_per_theme_sk_ticket,
  next_contact_per_theme_detail_sk_ticket,
  flag_back,
  sk_ticket_penalized,
  ts_started_penalized,
  channel_penalized,
  theme_penalized,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day,
  NOW() AS ts_load
FROM
  fcr
WHERE
  rank_cte = 1
  AND DATE(ts_started) >= DATE('{load_start_date}') - INTERVAL 1 YEAR
  AND refined_direction = 'INBOUND'