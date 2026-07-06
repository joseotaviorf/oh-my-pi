WITH tm_fix AS (
    -- Fix v3: busca métricas de tempo diretamente por id_reservation, evitando o fan-out
    -- do join upstream (OR id_task) que copiava o mesmo valor para todas as reservas da task.
    SELECT
        id_reservation,
        total_queue_time,
        total_talk_time,
        total_handling_time
    FROM (
        SELECT
            id_reservation,
            total_queue_time,
            total_talk_time,
            total_handling_time,
            ROW_NUMBER() OVER (
                PARTITION BY id_reservation
                ORDER BY dt_created DESC
            ) AS rn
        FROM datalake_twilio_flex_insights_clean.conversation_time_metrics
        WHERE id_reservation IS NOT NULL
        AND year >= 2025
    ) t
    WHERE rn = 1
),
queue_calc AS (
    -- ✅ Calcula queue_time direto dos timestamps de reserva.
    -- Fórmula: ts_reservation_accepted - ts_reservation_created (segundos).
    -- Mesma lógica do relatório Twilio SLA — resolve NULLs e elimina diferença de 1-2s do Flex Insights.
    -- Reservas não atendidas (abandoned/timeout) → ts_reservation_accepted = NULL → retorna NULL
    -- → COALESCE abaixo cai para tm_fix como fallback.
    SELECT
        id_reservation,
        (unix_timestamp(ts_reservation_accepted) - unix_timestamp(ts_reservation_created)) AS queue_time_calc
    FROM datalake_customer_support.calls
    WHERE id_reservation        IS NOT NULL
      AND ts_reservation_created  IS NOT NULL
      AND ts_reservation_accepted IS NOT NULL
      AND ts_reservation_created >= date('2023-01-01')
),

fcc_last_department AS (
    SELECT
        fcc.sk_ticket,
        fcc.sk_support_session,
        COALESCE(
            NULLIF(fcc.sk_support_session, '-1'),
            CAST(fcc.sk_ticket AS STRING)
        ) AS sk_support_session_fallback_ticket,
        fcc.sk_department
    FROM dw_customer_support.fact_customer_contacts AS fcc
    WHERE
        fcc.is_interaction_answered = TRUE
        AND fcc.is_last_interaction = TRUE
        AND fcc.ts_task_created >= DATE('2025-01-01')
),

fcc_first_department AS (
    SELECT
        fcc.sk_ticket,
        fcc.sk_support_session,
        COALESCE(
            NULLIF(fcc.sk_support_session, '-1'),
            CAST(fcc.sk_ticket AS STRING)
        ) AS sk_support_session_fallback_ticket,
        fcc.sk_department
    FROM dw_customer_support.fact_customer_contacts AS fcc
    WHERE
        fcc.is_interaction_answered = TRUE
        AND fcc.is_first_interaction = TRUE
        AND fcc.ts_task_created >= DATE('2025-01-01')
),


fact_service AS (

-- Dados a nível ticket a partir de  2026-06-25 - histórico anterior inconsistente (ex: theme e BPO)

    SELECT
        sk_event,
        sk_support_session,
        CAST(sk_support_session AS STRING) AS sk_support_session_varchar,
        bpo_name,
        queue_name AS fila_twilio,
        SUBSTR(theme, 3, LENGTH(theme) - 4) AS theme,
        SUBSTR(theme_detail, 3, LENGTH(theme_detail) - 4) AS theme_detail,
        ROW_NUMBER() OVER(PARTITION BY sk_support_session ORDER BY ts_task_created DESC) AS rn_task 
    FROM dw_support_journey.fact_services
      WHERE dt_task_created >= DATE('2026-06-25')
          AND is_current = true
          AND sk_support_session IS NOT NULL
          AND sk_support_session != '-1'

),

satisfaction_ratings AS (

-- CSAT da fact_answer (pesquisas a partir de 2026-06-25 - histórico anterior inconsistente) 

    SELECT
    fa.sk_case,
    fa.sk_answer,
    fa.sk_ticket,
    fa.sk_support_session,
    CAST(fa.sk_ticket AS STRING) AS sk_ticket_string,
    COALESCE(
        NULLIF(CAST(fa.sk_support_session AS STRING), '-1'), 
        CAST(fa.sk_ticket AS STRING) 
    ) AS sk_support_session_fallback_ticket,
    fa.sk_survey,
    fa.satisfaction_score,
    fa.secondary_satisfaction_score,
    fa.is_solved,
    fa.ts_submitted,
    ROW_NUMBER() OVER (
        PARTITION BY COALESCE(
            NULLIF(CAST(fa.sk_support_session AS STRING), '-1'),
            CAST(fa.sk_ticket AS STRING)
        )
        ORDER BY fa.ts_submitted ASC
    ) AS rn
FROM dw_satisfaction_rating.fact_answer AS fa
LEFT JOIN datalake_satisfaction_rating.satisfaction_answers sa 
    ON sa.id_answer = fa.sk_answer
WHERE 
    fa.ts_submitted >= DATE '2026-06-25'
    AND (
        (sa.service_context IN ('call', 'call inapp') AND sa.score_description = 'resolution survey') OR 
        (sa.service_context NOT IN ('call', 'call inapp') OR sa.service_context IS NULL)
    )
),
segments_perspective AS (
    SELECT
      fcc.sk_interaction,
      fcc.sk_contact,
      fcc.sk_call,
      fcc.sk_session,
      fcc.sk_task,
      fcc.sk_ticket,
      fcc.sk_user,
      fcc.channel,
      'INBOUND' AS refined_direction,
      fcc.customer_phone_number AS customer_phone,
      fcc.customer_email,
      fcc.origin AS origin_fcc,
      CASE
        WHEN fcc.origin = 'in app'   THEN CONCAT(fcc.channel, ' in app')
        WHEN fcc.channel IN ('call') THEN 'call inbound'
        ELSE fcc.origin
      END AS ticket_origin,
      '' AS origin_ft,
      fcc.is_contact_answered   AS is_answered,
      fcc.is_interaction_answered,
      fcc.is_first_interaction,
      fcc.is_last_interaction,
      fcc.is_first_department_interaction,
      fcc.is_per_team_task      AS per_team_flag,
      UPPER(fcc.status)         AS status,
      COALESCE(fcc.ts_reservation_created, fcc.ts_task_created) - INTERVAL '3' HOUR AS ts_reservation_created,
      NULL AS average_reply_time,

      -- ✅ queue_time — prioridade de fontes:
      --   1. qc.queue_time_calc   → ts_reservation_accepted - ts_reservation_created (primário)
      --                             Fonte exata, mesma lógica do Twilio SLA.
      --   2. tm_fix.total_queue_time → Flex Insights por id_reservation (fallback)
      --                             Usado quando ts_reservation_accepted = NULL (abandoned/timeout).
      --   3. NULL                 → sem nenhuma das duas fontes.
      --
      -- Guard >1800s: NULLifica valores que representam tempo acumulado da task inteira
      -- em vez da reserva específica (indica fcc.sk_reservation apontando para reserva errada).
      -- Fix definitivo para esses casos requer corrigir sk_reservation em fact_customer_contacts.
      --
      -- NÃO usar como fallback:
      --   • fcc.total_queue_time  → fan-out upstream: mesmo valor para todas as reservas da task.
      --   • fcc.first_reply_time  → waiting_time_sec acumulativo por task, não por reserva.
      CASE
        WHEN COALESCE(qc.queue_time_calc, tm_fix.total_queue_time) > 1800 THEN NULL
        ELSE      COALESCE(qc.queue_time_calc, tm_fix.total_queue_time)
      END AS queue_time,

      -- talk_time e handling_time: tm_fix por id_reservation, fallback fcc para chats.
      -- Chats têm sk_reservation = NULL → tm_fix retorna NULL → COALESCE usa fcc (sem fan-out).
      COALESCE(tm_fix.total_talk_time,     fcc.total_talk_time)     AS talk_time,
      COALESCE(tm_fix.total_handling_time, fcc.total_handling_time) AS handling_time,

      -- first_response_time: semântica original mantida.
      -- Calls = waiting_time_sec (acumulativo por task). Chats = seconds_to_first_response.
      -- Métrica diferente de queue_time — não substituível por queue_calc.
      fcc.first_reply_time AS first_response_time,

      fcc.quinto_andar_phone_number,
      CASE
        WHEN fcc.sk_ticket IS NOT NULL THEN TRUE
        WHEN fcc.sk_ticket > 0         THEN TRUE
        ELSE FALSE
      END AS has_ticket_created,
      CASE
        WHEN dd.department = '[AeC] CX Pagamentos [FRONT] [POS]'  THEN 'CX Pagamentos [FRONT] [POS]'
        WHEN dd.department = '[AeC] CX Rescisão [FRONT] [POS]'    THEN 'CX Rescisão [FRONT] [POS]'
        WHEN dd.department = '[AeC] CX Mudança [FRONT] [POS]'     THEN 'CX Mudança [FRONT] [POS]'
        WHEN dd.department = '[AeC] CX Reparos [FRONT] [POS]'     THEN 'CX Reparos [FRONT] [POS]'
        WHEN dd.department = '[AeC] CX Propostas [FRONT] [PRE]'   THEN 'CX Propostas [FRONT] [PRE]'
        WHEN dd.department = '[AeC] CX Ongoing [FRONT] [POS]'   THEN 'CX Ongoing [FRONT] [POS]'
        WHEN dd.department = '[AeC] CX Visitas [FRONT] [PRE]'     THEN 'CX Visitas [FRONT] [PRE]'
        WHEN dd.department = '[AeC] CX Parceiros [FRONT] [PRE]'   THEN 'CX Parceiros [FRONT] [PRE]'
        WHEN dd.department = '[AeC] Consultores imobiliários 5A'  THEN 'Consultores imobiliários 5A'
        WHEN dd.department = '[AeC] CX Parceiros Compra e Venda [FRONT]' THEN 'CX Parceiros Compra e Venda [FRONT]'
        ELSE dd.department
      END AS department,
      dd.team,
      dd.area,
      dd.front_or_back,
      dd.is_partner,
      dd.journey_step,
      dtax.customer_type_tag AS customer_type,  -- dado a partir de 2026-06-25 ausente, devido a migração ZD
      dtax.motivation,            -- dado a partir de 2026-06-25 ausente, devido a migração ZD
      COALESCE(dtax.theme,fs.theme)                   AS theme, 
      COALESCE(dtax.theme_detail,fs.theme_detail)     AS theme_detail,
      dtax.journey,               -- dado a partir de 2026-06-25 ausente, devido a migração ZD
      dtax.sub_journey,           -- dado a partir de 2026-06-25 ausente, devido a migração ZD
      dtax.line_owner,            -- dado a partir de 2026-06-25 ausente, devido a migração ZD
      da.email                                                               AS agent_email,
      da.agent_manager                                                       AS agent_manager,
      da.full_name                                                           AS agent_full_name,
      da.agent_organization,
      da.dt_agent_start                                                      AS agent_dt_start, -- dado a partir de 2026-06-25 ausente, devido a migração ZD
      FIRST_VALUE(da.email)              OVER (PARTITION BY fcc.sk_ticket ORDER BY fcc.ts_reservation_created ASC)  AS first_agent_email,
      FIRST_VALUE(da.email)              OVER (PARTITION BY fcc.sk_ticket ORDER BY fcc.ts_reservation_created DESC) AS last_agent_email,
      FIRST_VALUE(da.agent_organization) OVER (PARTITION BY fcc.sk_ticket ORDER BY fcc.ts_reservation_created DESC) AS last_agent_organization,
      ROW_NUMBER() OVER (PARTITION BY fcc.sk_contact ORDER BY fcc.ts_reservation_created) AS interaction_number,
      CASE
        WHEN dd.team IN ('Visits', 'Propostas', 'Moving', 'CX Partners', 'CX Compra e Venda', 'CIQ') THEN 'Pré'
        WHEN dd.team IN ('Repairs/Ongoing Front', 'Payments', 'Offboarding Front')                   THEN 'Pós'
        ELSE NULL
      END AS front_pre_pos,
      dt.tags,                  -- dado a partir de 2026-06-25 ausente, devido a migração ZD
      CASE
        WHEN dd_last.department = '[AeC] CX Pagamentos [FRONT] [POS]'  THEN 'CX Pagamentos [FRONT] [POS]'
        WHEN dd_last.department = '[AeC] CX Rescisão [FRONT] [POS]'    THEN 'CX Rescisão [FRONT] [POS]'
        WHEN dd_last.department = '[AeC] CX Mudança [FRONT] [POS]'     THEN 'CX Mudança [FRONT] [POS]'
        WHEN dd_last.department = '[AeC] CX Reparos [FRONT] [POS]'     THEN 'CX Reparos [FRONT] [POS]'
        WHEN dd_last.department = '[AeC] CX Propostas [FRONT] [PRE]'   THEN 'CX Propostas [FRONT] [PRE]'
        WHEN dd_last.department = '[AeC] CX Visitas [FRONT] [PRE]'     THEN 'CX Visitas [FRONT] [PRE]'
        WHEN dd_last.department = '[AeC] CX Parceiros [FRONT] [PRE]'   THEN 'CX Parceiros [FRONT] [PRE]'
        WHEN dd_last.department = '[AeC] Consultores imobiliários 5A'  THEN 'Consultores imobiliários 5A'
        WHEN dd_last.department = '[AeC] CX Parceiros Compra e Venda [FRONT]' THEN 'CX Parceiros Compra e Venda [FRONT]'
        ELSE dd_last.department
      END AS last_department,
      dd_last.team AS last_team,
      dd_last.area AS last_area,
      CASE
        WHEN dd_first.department = '[AeC] CX Pagamentos [FRONT] [POS]'  THEN 'CX Pagamentos [FRONT] [POS]'
        WHEN dd_first.department = '[AeC] CX Rescisão [FRONT] [POS]'    THEN 'CX Rescisão [FRONT] [POS]'
        WHEN dd_first.department = '[AeC] CX Mudança [FRONT] [POS]'     THEN 'CX Mudança [FRONT] [POS]'
        WHEN dd_first.department = '[AeC] CX Reparos [FRONT] [POS]'     THEN 'CX Reparos [FRONT] [POS]'
        WHEN dd_first.department = '[AeC] CX Propostas [FRONT] [PRE]'   THEN 'CX Propostas [FRONT] [PRE]'
        WHEN dd_first.department = '[AeC] CX Visitas [FRONT] [PRE]'     THEN 'CX Visitas [FRONT] [PRE]'
        WHEN dd_first.department = '[AeC] CX Parceiros [FRONT] [PRE]'   THEN 'CX Parceiros [FRONT] [PRE]'
        WHEN dd_first.department = '[AeC] Consultores imobiliários 5A'  THEN 'Consultores imobiliários 5A'
        WHEN dd_first.department = '[AeC] CX Parceiros Compra e Venda [FRONT]' THEN 'CX Parceiros Compra e Venda [FRONT]'
        ELSE dd_first.department
      END AS first_department,
      dd_first.team AS first_team,
      dd_first.area AS first_area,
      dd_prev.department AS transferred_from,
      dd_prev.team       AS transferred_from_team,
      dd_prev.area       AS prev_area,
      dd_next.department AS transferred_to,
      dd_next.team       AS transferred_to_team,
      dd_next.area       AS next_area,
      fcc.ts_task_created - INTERVAL '3' HOUR       AS ts_created,
      DATE(fcc.ts_task_created - INTERVAL '3' HOUR) AS dt_created,
      COALESCE(ftc.first_csat_score, sa.satisfaction_score)     AS first_csat_score,
      COALESCE(ftc.first_csat_comment,sa.respondent_comments)   AS first_csat_comment,        
      COALESCE(ftc.ts_first_response, sa.ts_submitted)          AS response_date,
      COALESCE(ftc.is_solved, sa.is_solved)                     AS resolution_survey,
      fcc.is_spoc_task,
      fcc.direction AS spoc_direction,
      REPLACE(get_json_object(custom_fields, '$["Session Source"]'), '#', '') AS session_source,
      fcc.sk_analyst,
      fii.step_name,
      fii.type AS type_call,
      s.bot,
      dt.group_name                                         -- dado a partir de 2026-06-25 ausente, devido a migração ZD

    FROM dw_customer_support.fact_customer_contacts AS fcc
    LEFT JOIN fact_service fs 
      ON fcc.sk_support_session = fs.sk_support_session
    LEFT JOIN dw_customer_support.dim_department AS dd
      ON dd.sk_department = fcc.sk_department
      
    LEFT JOIN fcc_last_department AS fld
      ON fld.sk_support_session_fallback_ticket = COALESCE(NULLIF(fcc.sk_support_session, '-1'),CAST(fcc.sk_ticket AS STRING))
    LEFT JOIN dw_customer_support.dim_department AS dd_last
      ON dd_last.sk_department = fld.sk_department
    LEFT JOIN fcc_first_department AS ffd
      ON ffd.sk_support_session_fallback_ticket = COALESCE(NULLIF(fcc.sk_support_session, '-1'),CAST(fcc.sk_ticket AS STRING))
      
    LEFT JOIN dw_customer_support.dim_department AS dd_first
      ON dd_first.sk_department = ffd.sk_department
    LEFT JOIN dw_customer_support.dim_department AS dd_prev
      ON dd_prev.sk_department = fcc.sk_prev_department
    LEFT JOIN dw_customer_support.dim_department AS dd_next
      ON dd_next.sk_department = fcc.sk_next_department
    LEFT JOIN dw_customer_support.dim_ticket AS dt
      ON dt.sk_ticket = fcc.sk_ticket
    LEFT JOIN dw_customer_support.dim_analyst AS da
      ON da.sk_analyst = fcc.sk_analyst
    LEFT JOIN dw_customer_support.dim_taxonomy AS dtax
      ON dtax.sk_taxonomy = dt.sk_taxonomy
    LEFT JOIN dw_satisfaction_rating.fact_ticket_csat AS ftc
      ON ftc.sk_ticket = fcc.sk_ticket
    LEFT JOIN satisfaction_ratings sa 
      ON fcc.sk_support_session = sa.sk_support_session
    LEFT JOIN dw_customer_support.fact_ivr_interactions AS fii
      ON fcc.sk_interaction = fii.sk_interaction
    LEFT JOIN datalake_chatbot.sessions AS s
      ON fcc.sk_session = CAST(s.id_sauron_session AS STRING)
    LEFT JOIN tm_fix
      ON tm_fix.id_reservation = fcc.sk_reservation
    LEFT JOIN queue_calc AS qc
      ON qc.id_reservation = fcc.sk_reservation

    WHERE
      fcc.channel IN ('chat','call')
      AND fcc.origin NOT IN ('outbound')
      AND fcc.ts_task_created >= DATE('2025-01-01')
),
contacts AS (
    SELECT
        sk_contact,
        COUNT(sk_interaction) AS vol_interaction
    FROM dw_customer_support.fact_customer_contacts
    WHERE DATE(ts_task_created) >= DATE('2023-01-01')
    GROUP BY 1
),
analyst_start AS (
    SELECT
        da.email        AS email,
        MIN(ts_created) AS start_date
    FROM dw_customer_support.fact_tickets AS ft
    LEFT JOIN dw_customer_support.dim_analyst AS da
      ON ft.sk_last_analyst = da.sk_analyst
    WHERE ft.ts_created >= DATE('2023-01-01')
    GROUP BY 1
),

first_resolution AS (
    SELECT
        da.email                  AS email,
        MIN(fcc.ts_reservation_ended) AS first_resolution
    FROM dw_customer_support.fact_customer_contacts AS fcc
    LEFT JOIN dw_customer_support.dim_analyst AS da
      ON fcc.sk_analyst = da.sk_analyst
    WHERE fcc.ts_task_created >= DATE('2023-01-01')
      AND fcc.ts_reservation_ended IS NOT NULL
    GROUP BY 1

)

SELECT
    sp.sk_interaction,
    sp.sk_contact,
    sp.sk_call,
    sp.sk_session,
    sp.sk_task,
    sp.sk_ticket,
    sp.sk_user,
    sp.channel,
    sp.refined_direction,
    sp.customer_phone,
    sp.customer_email,
    sp.origin_fcc,
    sp.ticket_origin,
    sp.origin_ft,
    sp.is_answered,
    sp.is_interaction_answered,
    sp.is_first_interaction,
    sp.is_last_interaction,
    sp.is_first_department_interaction,
    sp.per_team_flag,
    sp.status,
    sp.ts_reservation_created,
    sp.average_reply_time,
    sp.queue_time,
    sp.talk_time,
    sp.handling_time,
    sp.first_response_time,
    sp.quinto_andar_phone_number,
    sp.has_ticket_created,
    sp.department,
    sp.team,
    sp.area,
    sp.front_or_back,
    sp.is_partner,
    sp.journey_step,
    sp.customer_type,
    sp.motivation,
    sp.theme,
    sp.theme_detail,
    sp.journey,
    sp.sub_journey,
    sp.line_owner,
    sp.agent_email,
    sp.agent_manager,
    sp.agent_full_name,
    sp.agent_organization,
    sp.agent_dt_start,
    sp.first_agent_email,
    sp.last_agent_email,
    sp.last_agent_organization,
    sp.interaction_number,
    sp.front_pre_pos,
    sp.tags,
    sp.last_department,
    sp.last_team,
    sp.last_area,
    sp.first_department,
    sp.first_team,
    sp.first_area,
    sp.transferred_from,
    sp.transferred_from_team,
    sp.transferred_to,
    sp.transferred_to_team,
    sp.next_area,
    sp.ts_created,
    sp.dt_created,
    sp.first_csat_score,
    sp.first_csat_comment,
    sp.response_date,
    sp.resolution_survey,
    sp.is_spoc_task,
    sp.spoc_direction,
    sp.session_source,
    sp.sk_analyst,
    sp.step_name,
    sp.type_call,
    sp.bot,
    sp.group_name,
    COALESCE(co.company_name, co2.company_name) AS company_name,
    CASE
      WHEN sp.status = 'TRANSFERRED'
        AND sp.transferred_to != sp.last_department
        AND c.vol_interaction > 2               THEN 'human_error'
      WHEN sp.status = 'TRANSFERRED'            THEN 'bot_error'
      ELSE 'no_transfer'
    END AS transfer_reason,
    CASE
      WHEN sp.status = 'TRANSFERRED'
        AND (sp.first_department = sp.last_department OR sp.transferred_to != sp.last_department) THEN 'human_error'
      ELSE 'bot_error'
    END AS transfer_reason_teste,
    CASE
      WHEN sp.is_last_interaction = TRUE  AND sp.department != sp.first_department                                   THEN 'bot_error'
      WHEN sp.is_last_interaction = FALSE AND sp.transferred_to != sp.last_department AND sp.status = 'TRANSFERRED' THEN 'human_error'
      WHEN sp.is_last_interaction = FALSE AND sp.transferred_to = sp.last_department  AND sp.status = 'TRANSFERRED' THEN 'department_correction'
    END AS transfer_reason_detailed,
    ast.start_date      AS analyst_start_date,
    fr.first_resolution AS first_resolution_analyst,
    CASE WHEN sp.queue_time >= 10000 THEN 'Sim' ELSE 'Não' END AS queue_time_10k_sec,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load


FROM segments_perspective AS sp
LEFT JOIN analyst_start AS ast
  ON sp.agent_email = ast.email
LEFT JOIN dw_public.dim_company_3p_partners AS co
  ON sp.customer_email = co.e_mail
LEFT JOIN dw_public.dim_company_3p_partners AS co2
  ON sp.customer_phone = co2.phone
LEFT JOIN contacts AS c
  ON c.sk_contact = sp.sk_contact
LEFT JOIN first_resolution AS fr
  ON sp.agent_email = fr.email
WHERE 
  DATE(sp.dt_created) BETWEEN DATE('{load_start_date}') - INTERVAL '6' MONTH AND DATE('{load_end_date}')
  AND sp.area = 'CX'
