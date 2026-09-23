WITH base_fcc AS (
    SELECT *
    FROM dw_customer_support.fact_customer_contacts
    WHERE ts_task_created >= '{load_start_date}'
      AND ts_task_created <= '{load_end_date}'
),

tm_fix AS (
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
    SELECT
        id_reservation,
        (unix_timestamp(ts_reservation_accepted) - unix_timestamp(ts_reservation_created)) AS queue_time_calc
    FROM datalake_customer_support.calls
    WHERE id_reservation IS NOT NULL
      AND ts_reservation_created IS NOT NULL
      AND ts_reservation_accepted IS NOT NULL
      AND ts_reservation_created >= '{load_start_date}'
      AND ts_reservation_created <= '{load_end_date}'
),

fcc_dept_agg AS (
    SELECT
        COALESCE(NULLIF(sk_support_session, '-1'), CAST(sk_ticket AS STRING)) AS sk_support_session_fallback_ticket,
        MAX(CASE WHEN is_first_interaction = TRUE THEN sk_department END) AS first_sk_department,
        MAX(CASE WHEN is_last_interaction = TRUE THEN sk_department END) AS last_sk_department
    FROM base_fcc
    WHERE is_interaction_answered = TRUE
      AND (is_first_interaction = TRUE OR is_last_interaction = TRUE)
    GROUP BY 1
),

fact_service AS (
    SELECT
        sk_support_session,
        sk_task,
        SUBSTR(theme, 3, LENGTH(theme) - 4) AS theme,
        SUBSTR(theme_detail, 3, LENGTH(theme_detail) - 4) AS theme_detail,
        dt_task_created
    FROM dw_support_journey.fact_services
    WHERE dt_task_created >='{load_start_date}'
      AND dt_task_created <= '{load_end_date}'
      AND is_current = TRUE
      AND sk_support_session IS NOT NULL
      AND sk_support_session != '-1'
),

satisfaction_ratings AS (
    SELECT
        sk_support_session,
        satisfaction_score,
        is_solved,
        ts_submitted
    FROM (
        SELECT
            fa.sk_support_session,
            fa.satisfaction_score,
            fa.is_solved,
            fa.ts_submitted,
            ROW_NUMBER() OVER (
                PARTITION BY fa.sk_support_session
                ORDER BY fa.ts_submitted DESC
            ) AS rn
        FROM dw_satisfaction_rating.fact_answer AS fa
        LEFT JOIN datalake_satisfaction_rating.satisfaction_answers sa
          ON sa.id_answer = fa.sk_answer
        WHERE
          fa.ts_submitted >= '{load_start_date}'
          AND fa.ts_submitted <= '{load_end_date}'
          AND (
              (sa.service_context IN ('call', 'call inapp') AND sa.score_description = 'satisfaction evaluation')
           OR (sa.service_context NOT IN ('call', 'call inapp') OR sa.service_context IS NULL)
          )
    ) sub
    WHERE rn = 1
),

contacts AS (
    SELECT
        sk_contact,
        COUNT(sk_interaction) AS vol_interaction
    FROM base_fcc
    GROUP BY 1
),

first_resolution AS (
    SELECT
        da.email AS email,
        MIN(fcc.ts_reservation_ended) AS first_resolution
    FROM base_fcc AS fcc
    LEFT JOIN dw_customer_support.dim_analyst AS da
      ON fcc.sk_analyst = da.sk_analyst
    WHERE fcc.ts_reservation_ended IS NOT NULL
    GROUP BY 1
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
      fcc.is_contact_answered AS is_answered,
      fcc.is_interaction_answered,
      fcc.is_first_interaction,
      fcc.is_last_interaction,
      fcc.is_first_department_interaction,
      fcc.is_per_team_task AS per_team_flag,
      UPPER(CASE
        WHEN fcc.outcome = 'task idled' THEN 'idled'
        WHEN fcc.outcome = 'session expired' THEN 'expired'
        WHEN fcc.outcome = 'task completed' THEN 'completed'
        WHEN fcc.outcome = 'task transferred' THEN 'transferred'
        WHEN fcc.outcome IS NULL THEN fcc.status
        ELSE fcc.status 
      END) AS status,
      COALESCE(fcc.ts_reservation_created, fcc.ts_task_created) - INTERVAL '3' HOUR AS ts_reservation_created,
      CAST(NULL AS DOUBLE) AS average_reply_time,
      CASE
        WHEN COALESCE(qc.queue_time_calc, tm_fix.total_queue_time) > 1800 THEN NULL
        ELSE COALESCE(qc.queue_time_calc, tm_fix.total_queue_time)
      END AS queue_time,
      COALESCE(tm_fix.total_talk_time, fcc.total_talk_time) AS talk_time,
      COALESCE(tm_fix.total_handling_time, fcc.total_handling_time) AS handling_time,
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
        WHEN dd.department = '[AeC] CX Ongoing [FRONT] [POS]'     THEN 'CX Ongoing [FRONT] [POS]'
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
      dtax.customer_type_tag AS customer_type,
      dtax.motivation,
      COALESCE(dtax.theme, fs.theme) AS theme,
      COALESCE(dtax.theme_detail, fs.theme_detail) AS theme_detail,
      dtax.journey,
      dtax.sub_journey,
      dtax.line_owner,
      da.email AS agent_email,
      da.agent_manager AS agent_manager,
      da.full_name AS agent_full_name,
      da.agent_organization,
      da.dt_agent_start AS agent_dt_start,
      FIRST_VALUE(da.email) OVER (PARTITION BY fcc.sk_ticket ORDER BY fcc.ts_reservation_created ASC) AS first_agent_email,
      FIRST_VALUE(da.email) OVER (PARTITION BY fcc.sk_ticket ORDER BY fcc.ts_reservation_created DESC) AS last_agent_email,
      FIRST_VALUE(da.agent_organization) OVER (PARTITION BY fcc.sk_ticket ORDER BY fcc.ts_reservation_created DESC) AS last_agent_organization,
      ROW_NUMBER() OVER (PARTITION BY fcc.sk_contact ORDER BY fcc.ts_reservation_created) AS interaction_number,
      CASE
        WHEN dd.team IN ('Visits', 'Propostas', 'Moving', 'CX Partners', 'CX Compra e Venda', 'CIQ') THEN 'Pré'
        WHEN dd.team IN ('Repairs/Ongoing Front', 'Payments', 'Offboarding Front') THEN 'Pós'
        ELSE NULL
      END AS front_pre_pos,
      dt.tags,
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
      dd_prev.team AS transferred_from_team,
      dd_prev.area AS prev_area,
      dd_next.department AS transferred_to,
      dd_next.team AS transferred_to_team,
      dd_next.area AS next_area,
      fcc.ts_task_created - INTERVAL '3' HOUR AS ts_created,
      DATE(fcc.ts_task_created - INTERVAL '3' HOUR) AS dt_created,
      COALESCE(ftc.first_csat_score, sa.satisfaction_score) AS first_csat_score,
      ftc.first_csat_comment AS first_csat_comment,
      COALESCE(ftc.ts_first_response, sa.ts_submitted) AS response_date,
      COALESCE(ftc.is_solved, sa.is_solved) AS resolution_survey,
      fcc.is_spoc_task,
      fcc.direction,
      REPLACE(get_json_object(custom_fields, '$["Session Source"]'), '#', '') AS session_source,
      fcc.sk_analyst,
      fii.step_name,
      fii.type AS type_call,
      s.bot,
      dt.group_name
    FROM base_fcc AS fcc
    LEFT JOIN fact_service fs
      ON fcc.sk_task = fs.sk_task AND fs.dt_task_created >= '2026-06-25'
    LEFT JOIN dw_customer_support.dim_department AS dd
      ON dd.sk_department = fcc.sk_department
    LEFT JOIN fcc_dept_agg AS fda
      ON fda.sk_support_session_fallback_ticket = COALESCE(NULLIF(fcc.sk_support_session, '-1'), CAST(fcc.sk_ticket AS STRING))
    LEFT JOIN dw_customer_support.dim_department AS dd_last
      ON dd_last.sk_department = fda.last_sk_department
    LEFT JOIN dw_customer_support.dim_department AS dd_first
      ON dd_first.sk_department = fda.first_sk_department
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
      ON fcc.sk_support_session = sa.sk_support_session AND sa.ts_submitted >= '2026-06-25'
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
      AND fcc.direction IN ('inbound')
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
    sp.direction,
    sp.session_source,
    sp.sk_analyst,
    sp.step_name,
    sp.type_call,
    sp.bot,
    sp.group_name,
    CAST(NULL AS STRING) AS company_name,
    CASE
      WHEN sp.status = 'TRANSFERRED'
        AND sp.transferred_to != sp.last_department
        AND c.vol_interaction > 2 THEN 'human_error'
      WHEN sp.status = 'TRANSFERRED' THEN 'bot_error'
      ELSE 'no_transfer'
    END AS transfer_reason,
    CASE
      WHEN sp.status = 'TRANSFERRED'
        AND (sp.first_department = sp.last_department OR sp.transferred_to != sp.last_department) THEN 'human_error'
      ELSE 'bot_error'
    END AS transfer_reason_teste,
    CASE
      WHEN sp.is_last_interaction = TRUE AND sp.department != sp.first_department THEN 'bot_error'
      WHEN sp.is_last_interaction = FALSE AND sp.transferred_to != sp.last_department AND sp.status = 'TRANSFERRED' THEN 'human_error'
      WHEN sp.is_last_interaction = FALSE AND sp.transferred_to = sp.last_department AND sp.status = 'TRANSFERRED' THEN 'department_correction'
    END AS transfer_reason_detailed,
    fr.first_resolution AS first_resolution_analyst,
    CASE WHEN sp.queue_time >= 10000 THEN 'Sim' ELSE 'Não' END AS queue_time_10k_sec,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM segments_perspective AS sp
LEFT JOIN contacts AS c
  ON c.sk_contact = sp.sk_contact
LEFT JOIN first_resolution AS fr
  ON sp.agent_email = fr.email
