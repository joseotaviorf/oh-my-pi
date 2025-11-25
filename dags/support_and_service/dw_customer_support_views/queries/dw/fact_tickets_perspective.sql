WITH
  sessions_filtered AS (
    SELECT id_sauron_session, ts_created, bot
    FROM datalake_chatbot.sessions
    WHERE ts_created >= date('2025-01-01')
  ),
  segments AS (
    SELECT
      fcc.sk_ticket,
      MIN(fcc.ts_task_created - interval '3' hour) as ts_task_created,
      SUM(fcc.total_talk_time) as total_talk_time,
      COUNT(DISTINCT fcc.sk_interaction) as number_of_interaction, 
      MAX(s.bot) bot
    FROM dw_customer_support.fact_customer_contacts fcc
    LEFT JOIN sessions_filtered s
      ON fcc.sk_session = CAST(s.id_sauron_session as STRING)
    WHERE fcc.ts_task_created >= date('2025-01-01')
    GROUP BY 1
  ),
 fact_ticket_csat AS (
    SELECT
        ftc.sk_ticket,
        ftc.last_csat_score,
        ftc.last_csat_comment,
        ftc.ts_last_response,
        ftc.first_csat_score,
        ftc.first_csat_comment,
        ftc.ts_first_response,
        ftc.is_solved
        FROM dw_satisfaction_rating.fact_ticket_csat ftc
        WHERE ftc.ts_first_response >= date('2024-01-01')
        QUALIFY
        ROW_NUMBER() OVER (PARTITION BY sk_ticket ORDER BY ts_first_response DESC) = 1
  )
    SELECT
      ft.sk_ticket,
      ft.sk_user,
      COALESCE(ft.sk_user,ft.sk_contract) AS sk_user_contract,
      ft.sk_contract,
      ft.sk_session,
      ft.channel,
      dit.status,
      ftc.last_csat_score, 
      ftc.last_csat_comment, 
      ftc.ts_last_response AS last_csat_ts_response, 
      ftc.first_csat_score, 
      ftc.first_csat_comment, 
      ftc.ts_first_response AS first_csat_ts_response, 
      ft.replies,
      ft.reopens,
      ft.front_or_back,
      CASE
        WHEN ftc.sk_ticket IS NOT NULL THEN TRUE
        ELSE FALSE
      END AS has_answered_csat,
      ft.is_ticket_rate,
      ft.ticket_rate_weight,
      DATE_DIFF(DAY, DATE(ft.ts_created), DATE(ft.ts_solved)) AS ticket_age,
      dit.type AS ticket_type,
      dd_first.department AS first_department, 
      dd_last.department AS last_department, 
      CASE
        WHEN dd_last.department IN (
          'CX Mudança [FRONT] [POS]',
          'CX Parceiros Compra e Venda [FRONT]',
          'CX Parceiros [FRONT] [PRE]',
          'CX Parceiros da Portaria [FRONT] [PRE]',
          'CX Propostas [FRONT] [PRE]',
          'CX Visitas [FRONT] [PRE]',
          'Consultores imobiliários 5A'
        ) THEN 'Pré'
        WHEN dd_last.department IN (
          'CX Pagamentos [FRONT] [POS]',
          'CX Reparos [FRONT] [POS]',
          'CX Rescisão [FRONT] [POS]'
        )
        THEN 'Pós'
        ELSE NULL
      END AS pre_pos_front,
      da_first.email AS first_agent_email,
      da_first.agent_manager AS first_agent_manager,
      da_first.agent_organization AS first_agent_organization,
      da_last.email AS last_agent_email,
      da_last.agent_manager AS last_agent_manager,
      da_last.agent_organization AS last_agent_organization,
      DATE_DIFF(DAY, ft.ts_updated, CURRENT_DATE) AS days_since_last_update,
      ft.reply_time_min_business AS minutes_first_reply_time_business,
      ft.reply_time_min_calendar AS minutes_first_reply_time_calendar,
      ft.is_backlog_in_time AS is_ticket_solved_within_sla,
      ft.days_elapsed_business AS days_worked,
      ft.days_elapsed_calendar AS days_worked_with_days_off,
      ft.sla_target,
      ft.ticket_origin AS ticket_origin,
      seg.total_talk_time,
      seg.bot,
      at_timezone(from_iso8601_timestamp(ft.ts_latest_customer_comment), 'America/Sao_Paulo') AS ts_latest_customer_comment,
      at_timezone(from_iso8601_timestamp(ft.ts_latest_analyst_comment), 'America/Sao_Paulo') AS ts_latest_analyst_comment,
      seg.ts_task_created,
      ft.ts_created,
      ft.ts_updated,
      CASE
        WHEN seg.ts_task_created IS NULL THEN ft.ts_created
        ELSE LEAST(ft.ts_created,seg.ts_task_created)
      END AS ts_started_new, 
      DATE_TRUNC('week', ft.ts_created) AS ts_started_week,
      ft.ts_closed,
      ft.ts_solved,
      ft.ts_last_move_to_final_group
    FROM dw_customer_support.fact_tickets AS ft
    LEFT JOIN fact_ticket_csat as ftc
      ON ftc.sk_ticket = ft.sk_ticket
    LEFT JOIN dw_customer_support.dim_department AS dd_last
      ON dd_last.sk_department = ft.sk_main_department
    LEFT JOIN dw_customer_support.dim_department AS dd_first
      ON dd_first.sk_department = ft.sk_first_department
    LEFT JOIN dw_customer_support.dim_analyst AS da_first
      ON da_first.sk_analyst = ft.sk_first_analyst
    LEFT JOIN dw_customer_support.dim_analyst AS da_last
      ON da_last.sk_analyst = ft.sk_last_analyst
    LEFT JOIN dw_customer_support.dim_ticket AS dit
      ON dit.sk_ticket = ft.sk_ticket
    LEFT JOIN segments AS seg
      ON seg.sk_ticket = ft.sk_ticket
    WHERE
      ft.sk_ticket IS NOT NULL
      AND ft.ts_created >= CAST('2024-01-01' AS DATE)