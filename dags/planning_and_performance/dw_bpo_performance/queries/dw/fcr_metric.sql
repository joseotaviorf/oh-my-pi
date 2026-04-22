WITH segments AS (
    SELECT
        ftm.sk_ticket,
        MAX(ftm.total_talk_time) AS total_talk_time
    FROM dw_customer_support.fact_customer_contacts ftm
    WHERE
        ftm.ts_task_created >= DATE('2024-01-01')
        AND ftm.is_interaction_answered = true
        AND ftm.is_last_interaction = true
    GROUP BY
        ftm.sk_ticket
),


tickets_perspective AS (
    SELECT
        ft.sk_ticket,
        ft.sk_user,
        ft.sk_contract,
        COALESCE(ft.sk_user, ft.sk_contract) AS sk_user_contract,
        ft.sk_session,
        ft.channel,
        dit.status,
        ftc.last_csat_score,
        ftc.last_csat_comment,
        ftc.ts_last_response AS last_csat_ts_response,
        ftc.first_csat_score,
        ftc.first_csat_comment,
        ftc.ts_first_response AS first_csat_ts_response,
        ftc.is_solved AS resolution_survey,
        ft.replies,
        ft.reopens,
        ft.front_or_back,
        CASE WHEN ftc.sk_ticket IS NOT NULL THEN TRUE ELSE FALSE END AS has_answered_csat,
        ft.is_ticket_rate,
        ft.ticket_rate_weight,
        ft.ts_created AS ts_started,
        ft.ts_closed,
        ft.ts_solved,
        dit.tags,
        dd_first.department AS first_department,
        dd_first.team AS first_team,
        dd_first.area AS first_area,
        dd_first.is_partner AS first_is_partner,
        dd_last.department AS last_department,
        dd_last.team AS last_team,
        dd_last.area AS last_area,
        dd_last.is_partner AS last_is_partner,
        dt.customer_type_tag AS customer_type,
        dt.motivation,
        dt.theme,
        dt.theme_detail,
        dt.journey,
        dt.sub_journey,
        -- Spark SQL utiliza get_json_object para extração simples
        get_json_object(dit.custom_fields, '$["[HUB] Jornada"]') AS jornada_hub,
        dt.line_owner,
        CASE
            WHEN ft.ticket_origin = 'call inapp'   THEN 'INBOUND'
            WHEN ft.ticket_origin = 'call inbound' THEN 'INBOUND'
            WHEN ft.ticket_origin = 'chat5a'        THEN 'INBOUND'
            WHEN ft.ticket_origin = 'call outbound'THEN 'OUTBOUND'
            ELSE UPPER(ft.direction)
        END AS refined_direction,
        CASE
            WHEN dit.ticket_via = 'whatsapp' THEN 'whatsapp'
            WHEN ft.channel   = 'cs email'   THEN 'zendesk email'
            ELSE ft.ticket_origin
        END AS refined_ticket_origin,
        da_first.email AS first_agent_email,
        da_first.agent_manager AS first_agent_manager,
        da_first.full_name AS first_agent_full_name,
        da_first.agent_organization AS first_agent_organization,
        da_first.dt_agent_start AS first_agent_dt_start,
        da_last.email AS last_agent_email,
        da_last.agent_manager AS last_agent_manager,
        da_last.full_name AS last_agent_full_name,
        da_last.agent_organization AS last_agent_organization,
        da_last.dt_agent_start AS last_agent_dt_start,
        ft.ts_updated AS ts_updated_local,
        -- Spark: DATEDIFF(end, start)
        DATEDIFF(CURRENT_DATE(), ft.ts_updated) AS days_since_last_update,
        ft.first_resolution_time_min_business AS minutes_first_reply_time_business,
        ft.first_resolution_time_min_calendar AS minutes_first_reply_time_calendar,
        ft.is_backlog_in_time AS is_ticket_solved_within_sla,
        ft.sla_target,
        calendar.is_brz_business_day,
        CASE
            WHEN dd_last.team IN ('Repairs/Ongoing Front', 'Repairs/Ongoing Back') THEN 'Reparos'
            WHEN dd_last.team IN ('Ongoing Back', 'Ong Back') THEN 'Ongoing'
            WHEN dd_last.team IN ('Rental Manager', 'Rental Manager Gold', 'Rental Manager CTL') THEN 'Rental Manager'
            WHEN dd_last.team IN ('Payments', 'Payments Ativo Back') THEN 'Payments'
            WHEN dd_last.team IN ('CX Partners', 'CX Compra e Venda', 'CX Partners For Sale') THEN 'Partners'
            WHEN dd_last.team IN ('Onboarding Back', 'Moving') THEN 'Onboarding'
            WHEN dd_last.team IN ('Offboarding Front', 'Offboarding Back') THEN 'Offboarding'
            WHEN dd_last.team IN ('ReclameAqui', 'Privacy', 'Casos Especiais', 'PROCON', 'Dados Bancários', 'Conta Comigo', 'Subsídios', 'Consumidor.Gov', 'Notificação Extrajudicial', 'Midias Ops', 'ReclameAqui - Grupo5A', 'Reversão de NPS') THEN 'CSI'
            ELSE dd_last.team
        END AS team_adjusted,
        sseg.total_talk_time AS total_talk_time_in_seconds,
        CASE WHEN sseg.total_talk_time <= 240 THEN TRUE ELSE FALSE END AS is_shortcall,
        CASE
            WHEN dit.tags LIKE '%tarefa_escalar_atendimento_front%' OR dit.tags LIKE '%magic_link_demanda%' OR dit.tags LIKE '%ticket_ativo%' THEN 'Front'
            WHEN dit.tags LIKE '%form_faq_portabilidade%' OR dit.tags LIKE '%form_faq%' THEN 'Faq'
            ELSE
                CASE
                    WHEN dit.ticket_via = 'api'   THEN 'Api / PWA'
                    WHEN dit.ticket_via = 'web'   THEN 'Web (quin.to/mensagem)'
                    WHEN dit.ticket_via = 'email' THEN 'E-mail'
                    ELSE dit.ticket_via
                END
        END AS canal_de_entrada
    FROM dw_customer_support.fact_tickets AS ft
    LEFT JOIN dw_satisfaction_rating.fact_ticket_csat AS ftc ON ftc.sk_ticket = ft.sk_ticket
    LEFT JOIN dw_customer_support.dim_department AS dd_last ON dd_last.sk_department = ft.sk_main_department
    LEFT JOIN dw_customer_support.dim_department AS dd_first ON dd_first.sk_department = ft.sk_first_department
    LEFT JOIN dw_customer_support.dim_taxonomy AS dt ON dt.sk_taxonomy = ft.sk_taxonomy
    LEFT JOIN dw_customer_support.dim_analyst AS da_first ON da_first.sk_analyst = ft.sk_last_analyst
    LEFT JOIN dw_customer_support.dim_analyst AS da_last ON da_last.sk_analyst = ft.sk_last_analyst
    LEFT JOIN dw_customer_support.dim_ticket AS dit ON dit.sk_ticket = ft.sk_ticket
    LEFT JOIN dw_public.dim_date AS calendar ON calendar.date = DATE(ft.ts_solved)
    LEFT JOIN segments AS sseg ON sseg.sk_ticket = ft.sk_ticket
    WHERE
        ft.ts_created >= DATE('2024-01-01')
        AND COALESCE(ft.sk_user, ft.sk_contract) > 0
        AND dd_last.area = 'CX'
        AND dd_last.area NOT LIKE '%MX%'
),


recontact_drilldown AS (
    SELECT
        tp.sk_ticket,
        tp.sk_user,
        tp.sk_user_contract,
        DATE(tp.ts_started) AS dt_ticket,
        -- Spark: DATE_ADD(start_date, num_days)
        DATE_ADD(DATE(tp.ts_started), -3) AS recontact_search_window_from,
        tp.ts_started AS recontact_search_window_until,
        CASE
            WHEN DATEDIFF(LEAD(DATE(tp.ts_started)) OVER (PARTITION BY tp.sk_user, tp.last_team ORDER BY tp.ts_started), DATE(tp.ts_started)) <= 4
            THEN CASE
                     WHEN tp.sk_ticket != LEAD(tp.sk_ticket) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started)
                      AND tp.ts_started != LEAD(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started)
                     THEN 1 ELSE 0
                 END
            ELSE 0
        END AS recontact_flag,
        CASE
            WHEN DATEDIFF(LEAD(DATE(tp.ts_started)) OVER (PARTITION BY tp.sk_user, tp.last_team, tp.theme ORDER BY tp.ts_started), DATE(tp.ts_started)) <= 4
            THEN CASE
                     WHEN tp.sk_ticket != LEAD(tp.sk_ticket) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started)
                      AND tp.ts_started != LEAD(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started)
                      AND tp.theme IS NOT NULL
                     THEN 1 ELSE 0
                 END
            ELSE 0
        END AS theme_recontact_flag,
        CASE
            WHEN DATEDIFF(LEAD(DATE(tp.ts_started)) OVER (PARTITION BY tp.sk_user, tp.last_team, tp.theme, tp.theme_detail ORDER BY tp.ts_started), DATE(tp.ts_started)) <= 4
            THEN CASE
                     WHEN tp.sk_ticket != LEAD(tp.sk_ticket) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme, tp.theme_detail ORDER BY tp.ts_started)
                      AND tp.ts_started != LEAD(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started)
                      AND tp.theme IS NOT NULL
                      AND tp.theme_detail IS NOT NULL
                     THEN 1 ELSE 0
                 END
            ELSE 0
        END AS theme_detail_recontact_flag,
        -- LEAD fields seguem a mesma lógica (exemplo de um campo abaixo)
        LEAD(tp.sk_ticket) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_sk_ticket,
        LEAD(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_ts_started,
        LEAD(tp.last_agent_email) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_agent,
        LEAD(tp.channel) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_channel,
        LEAD(tp.theme) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_theme,
        LEAD(tp.theme_detail) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_theme_detail,
        LEAD(tp.first_csat_score) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_csat,
        LEAD(tp.refined_direction) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started) AS previous_contact_direction,
        DATEDIFF(LEAD(DATE(tp.ts_started)) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme ORDER BY tp.ts_started), DATE(tp.ts_started)) AS days_since_last_contact
    FROM tickets_perspective AS tp
    WHERE
        tp.sk_user_contract > 0
        AND tp.last_area = 'CX'
        AND (tp.front_or_back = 'front' OR tp.last_department IN ('[WH] Credito [FRONT]', '[WH] Closing [FRONT]'))
        AND tp.last_department NOT IN ('Welcome Onboarding [BACK] [POS]', 'CX Welcome Onboarding [FRONT][POS]', 'EARLY DEMAND [CLOSING] [BACK]', 'FUP Carteirização B2C [CLO] [PRE] [BACK]', 'Closing Contratos [CLO] [PRE] [BACK]')
        AND tp.refined_direction = 'INBOUND'
        AND tp.channel IN ('chat', 'call', 'whatsapp')
),


back_penalizations AS (
    SELECT
        tp.*,
        CASE WHEN tp.channel = 'whatsapp' THEN 1 ELSE 0 END AS flag_back_wpp,
        CASE WHEN tp.refined_direction <> 'INBOUND' AND tp.front_or_back = 'back' THEN 1 ELSE 0 END AS flag_back_outbound,
        CASE WHEN tp.refined_direction <> 'INBOUND' AND tp.channel IN ('call', 'chat', 'email') THEN 1 ELSE 0 END AS flag_back_outbound_teste,
        CASE WHEN tp.front_or_back = 'back' THEN 1 ELSE 0 END AS flag_back,
        CASE WHEN (tp.replies >= 1 OR tp.reopens > 0) AND tp.front_or_back = 'back' THEN 1 ELSE 0 END AS flag_replies
    FROM tickets_perspective AS tp
    WHERE
        tp.sk_user_contract > 0
        AND tp.last_area = 'CX'
        AND (tp.front_or_back = 'back' OR tp.channel = 'whatsapp')
),


recontact_drilldown_per_bpo AS (
 SELECT
    tp.sk_ticket,
    tp.sk_user,
    tp.sk_user_contract,
    tp.last_team,
    tp.ts_started,


    -- Contato anterior
    LAG(tp.sk_ticket) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS prev_sk_ticket,
    LAG(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS prev_ts_started,
    LAG(tp.last_agent_email) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS prev_agent_email,
    LAG(tp.last_agent_organization) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS prev_agent_organization,


    -- Flag de recontato (olhando para trás): diferença entre 0 e 4 dias
    CASE
      WHEN LAG(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) IS NOT NULL
        AND DATEDIFF(
            CAST(tp.ts_started AS DATE),
            CAST(LAG(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS DATE)
        ) BETWEEN 0 AND 4
        AND tp.sk_ticket != LAG(tp.sk_ticket) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started)
        AND tp.ts_started != LAG(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started)
      THEN 1 ELSE 0
    END AS recontact_flag_per_bpo,


    -- Owner do recontato
    CASE
      WHEN LAG(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) IS NOT NULL
        AND DATEDIFF(
            CAST(tp.ts_started AS DATE),
            CAST(LAG(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started) AS DATE)
        ) BETWEEN 0 AND 4
      THEN LAG(tp.last_agent_organization) OVER (PARTITION BY tp.sk_user_contract, tp.last_team ORDER BY tp.ts_started)
      ELSE NULL
    END AS recontact_owner_org,


    -- Flag de recontato por tema (olhando para frente)
    CASE
        WHEN DATEDIFF(
            CAST(LEAD(tp.ts_started) OVER (PARTITION BY tp.sk_user, tp.last_team, tp.theme, tp.last_agent_organization ORDER BY tp.ts_started) AS DATE),
            CAST(tp.ts_started AS DATE)
        ) <= 4
        THEN CASE
                WHEN tp.sk_ticket != LEAD(tp.sk_ticket) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.theme, tp.last_agent_organization ORDER BY tp.ts_started)
                 AND tp.ts_started != LEAD(tp.ts_started) OVER (PARTITION BY tp.sk_user_contract, tp.last_team, tp.last_agent_organization ORDER BY tp.ts_started)
                 AND tp.theme IS NOT NULL
                THEN 1 ELSE 0
             END
        ELSE 0
    END AS theme_recontact_flag_bpo


FROM tickets_perspective tp
WHERE
    tp.sk_user_contract > 0
    AND tp.last_area = 'CX'
    AND (
      tp.front_or_back = 'front'
      OR tp.last_department IN ('[WH] Credito [FRONT]', '[WH] Closing [FRONT]')
    )
    AND tp.last_department NOT IN (
      'Welcome Onboarding [BACK] [POS]',
      'CX Welcome Onboarding [FRONT][POS]',
      'EARLY DEMAND [CLOSING] [BACK]',
      'FUP Carteirização B2C [CLO] [PRE] [BACK]',
      'Closing Contratos [CLO] [PRE] [BACK]'
    )
    AND tp.refined_direction = 'INBOUND'
    AND tp.channel IN ('chat', 'call', 'whatsapp')
),


temp AS (
SELECT
    tp.*,
    rd.recontact_search_window_from,
    rd.recontact_search_window_until,
    rd.recontact_flag,
    rd.theme_recontact_flag,
    rd.theme_detail_recontact_flag,
    rd.previous_contact_sk_ticket,
    rd.previous_contact_channel,
    rd.previous_agent,
    rd.previous_contact_ts_started,
    rd.previous_contact_theme,
    rd.previous_contact_theme_detail,
    rd.previous_contact_csat,
    rd.days_since_last_contact,
   
    -- ✅ Recontato atribuído à BPO do contato anterior
    rdb.recontact_flag_per_bpo,
    rdb.recontact_owner_org,
    rdb.prev_sk_ticket           AS prev_contact_sk_ticket_per_bpo,
    rdb.prev_ts_started          AS prev_contact_ts_started_per_bpo,
    rdb.prev_agent_email         AS prev_contact_agent_per_bpo,
    rdb.prev_agent_organization  AS prev_contact_org_per_bpo,
    rdb.theme_recontact_flag_bpo AS theme_recontact_flag_per_bpo,
   
    bpe.flag_back_outbound,
    bpe.flag_back_outbound_teste,
    bpe.flag_back_wpp,
    bpe.flag_back,
    bpe.flag_replies,
    bpe.sk_ticket AS sk_ticket_penalized,
    bpe.ts_started AS ts_started_penalized,
    bpe.channel AS channel_penalized,
    bpe.theme   AS theme_penalized,
   
    CASE
        WHEN bpe.sk_user_contract IS NULL THEN 1
        ELSE ROW_NUMBER() OVER (
                PARTITION BY tp.sk_ticket
                ORDER BY CAST(bpe.ts_started AS TIMESTAMP) ASC
             )
    END AS rank_cte
FROM tickets_perspective AS tp
LEFT JOIN recontact_drilldown AS rd
    ON rd.sk_ticket = tp.sk_ticket
LEFT JOIN recontact_drilldown_per_bpo AS rdb
    ON rdb.sk_ticket = tp.sk_ticket
LEFT JOIN back_penalizations AS bpe
    ON tp.sk_user_contract = bpe.sk_user_contract
   AND tp.team_adjusted   = bpe.team_adjusted
   AND tp.ts_started      <= bpe.ts_started
   -- Ajuste DATEDIFF para Spark SQL (Databricks)
   AND DATEDIFF(CAST(bpe.ts_started AS DATE), CAST(tp.ts_started AS DATE)) <= 4
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
        'CX Plaquinhas [FRONT] [PRE]',
        'CX Entrada no imóvel [ONB] [POS] [FRONT]',
        'CX Pagamentos N1 [PAY] [POS] [FRONT]',
        'CX Durante a locação e reparos [POS] [FRONT]',
        'CX Rescisão e Vistoria [OFF] [POS] [FRONT]',
        '[WH] Credito [FRONT]',
        '[WH] Closing [FRONT]',
        '[AeC] CX Pagamentos [FRONT] [POS]',
        '[AeC] CX Rescisão [FRONT] [POS]',
        '[AeC] CX Mudança [FRONT] [POS]',
        '[AeC] CX Reparos [FRONT] [POS]',
        '[AeC] CX Propostas [FRONT] [PRE]',
        '[AeC] CX Visitas [FRONT] [PRE]',
        '[AeC] CX Parceiros [FRONT] [PRE]',
        '[AeC] CX Ongoing [FRONT] [POS]',
        'CX Ongoing [FRONT] [POS]',
        '[AeC] Consultores imobiliários 5A',
        '[AeC] CX Parceiros Compra e Venda [FRONT]'
    )
),


pp_multi AS (
    SELECT
        dt_houses_owned as date,
        id_owner as sk_owner,
        ongoing_houses,
        is_pp_multi_active,
        CASE WHEN is_pp_multi_active = TRUE or ongoing_houses >= 5 THEN TRUE ELSE FALSE END AS is_pp_multi
    FROM datalake_pro_owners.daily_owner_houses_quantity_history ppm
    WHERE (ongoing_houses >= 5 OR is_pp_multi_active = TRUE)
),


first_resolution as (
  SELECT
    last_agent_email,
    min(ts_solved) as first_resolution
  FROM tickets_perspective
  GROUP BY 1
)


SELECT
    t.sk_ticket,
    t.ts_started,
    t.ts_solved,
    t.last_team,
    t.channel,
    t.last_agent_organization,
    t.flag_back,
    t.theme_recontact_flag,
    t.theme_recontact_flag_per_bpo,
    t.last_department,
    ppm.is_pp_multi,
    fr.first_resolution as first_resolution_last_agent,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM temp AS t
LEFT JOIN pp_multi as ppm on ppm.sk_owner = t.sk_user and date(t.ts_started) = ppm.date
LEFT JOIN first_resolution AS fr ON fr.last_agent_email = t.last_agent_email
WHERE
    t.rank_cte = 1
    AND DATE(t.ts_started) BETWEEN DATE('{load_start_date}') - INTERVAL '1' YEAR AND DATE_ADD(CURRENT_DATE(), -4)
    AND t.refined_direction = 'INBOUND'
    AND T.last_area = 'CX'

