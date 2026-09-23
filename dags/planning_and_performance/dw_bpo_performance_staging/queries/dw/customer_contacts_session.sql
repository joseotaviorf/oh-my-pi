WITH fact_service AS (
    SELECT
        sk_event,
        sk_support_session,
        CAST(sk_support_session AS STRING) AS sk_support_session_varchar,
        bpo_name,
        queue_name AS fila_twilio,
        SUBSTR(theme, 3, LENGTH(theme) - 4) AS theme,
        SUBSTR(theme_detail, 3, LENGTH(theme_detail) - 4) AS theme_detail,
        ROW_NUMBER() OVER(PARTITION BY sk_support_session ORDER BY ts_task_created DESC, sk_task_event DESC) AS rn_task
    FROM dw_support_journey.fact_services
      WHERE dt_task_created >= DATE_SUB(DATE('{load_start_date}'), 20) 
          AND dt_task_created <= DATE_ADD(DATE('{load_end_date}'), 20) 
          AND sk_support_session IS NOT NULL
          AND sk_support_session != '-1'
          AND queue_name not in ('IVR Events (no workers)')
),

------- Regra Incremental 

contacts_modified as (
SELECT 
fcc.sk_support_session
FROM dw_customer_support.fact_customer_contacts AS fcc
   WHERE fcc.ts_task_created >= DATE_SUB(DATE('{load_start_date}'), 20) 
        AND fcc.ts_task_created < DATE_ADD(DATE('{load_end_date}'), 20) 
        AND fcc.channel IN ('chat', 'call')
        AND fcc.is_interaction_answered = TRUE
UNION 
SELECT 
fa.sk_support_session 
FROM dw_satisfaction_rating.fact_answer AS fa
LEFT JOIN datalake_satisfaction_rating.satisfaction_answers sa 
        ON sa.id_answer = fa.sk_answer
    WHERE 1=1
    AND    fa.ts_submitted >= DATE_SUB(DATE('{load_start_date}'), 20) 
    AND fa.ts_submitted < DATE_ADD(DATE('{load_end_date}'), 20) 
      AND (
        (sa.service_context IN ('call','call inapp') AND sa.score_description = 'satisfaction evaluation') OR 
        (sa.service_context NOT IN ('call','call inapp')
        )
      )),

customer_contacts AS (
    SELECT
        fcc.sk_interaction,
        fcc.sk_contact,
        fcc.sk_call,
        fcc.sk_session,
        fcc.sk_support_session,
        fcc.sk_ticket,
        fcc.sk_task,
        fcc.sk_user,
        fcc.sk_analyst,

        CASE
            WHEN dd.department IN (
                '[AeC] CX Pagamentos [FRONT] [POS]',
                '[AeC] CX Ongoing [FRONT] [POS]',
                '[AeC] CX Rescisão [FRONT] [POS]',
                '[AeC] CX Mudança [FRONT] [POS]',
                '[AeC] CX Reparos [FRONT] [POS]',
                '[AeC] CX Propostas [FRONT] [PRE]',
                '[AeC] CX Visitas [FRONT] [PRE]',
                '[AeC] CX Parceiros [FRONT] [PRE]',
                '[AeC] Consultores imobiliários 5A',
                '[AeC] CX Parceiros Compra e Venda [FRONT]'
            ) THEN SUBSTR(dd.department, 7)
            ELSE dd.department
        END AS department,
        dd.area,
        dd.front_or_back,
        dd.team AS team,

        da.email          AS agent_email,
        da.agent_manager  AS agent_manager,
        da.full_name      AS agent_full_name,
        da.agent_organization,
        da.dt_agent_start AS agent_dt_start,
        dd_prev.department AS transferred_from,
        dd_prev.team       AS transferred_from_team,
        dd_prev.area       AS prev_area,
        dd_next.department AS transferred_to,
        dd_next.team       AS transferred_to_team,
        dd_next.area       AS next_area,
        fcc.origin                      AS origin_fcc,
        fcc.channel,
        fcc.customer_email,
        fcc.is_interaction_answered,
        fcc.is_contact_answered,
        fcc.is_first_interaction,
        fcc.is_last_interaction,
        fcc.is_first_department_interaction,
        fcc.quinto_andar_phone_number,
        fcc.is_spoc_task,

        fcc.customer_phone_number AS customer_phone,
        fcc.is_per_team_task      AS per_team_flag,
        fcc.first_reply_time      AS first_response_time,
        UPPER(fcc.status)         AS status,
        fcc.direction,
        fcc.ts_reservation_created,
        fcc.ts_task_created,
        fcc.total_talk_time,
        fcc.total_handling_time,
        fcc.ts_task_created - INTERVAL 3 HOURS        AS ts_created,
        DATE(fcc.ts_task_created - INTERVAL 3 HOURS)  AS dt_created,

        fs.theme,
        fs.theme_detail,
        COALESCE(CAST(fcc.sk_ticket AS STRING), fcc.sk_support_session) AS sk_session_key-- verificar como virá o sk_ticket após desligamento do ZD (será null ou -1?)
    FROM dw_customer_support.fact_customer_contacts AS fcc
    LEFT JOIN dw_customer_support.dim_department AS dd       ON dd.sk_department = fcc.sk_department
    LEFT JOIN dw_customer_support.dim_department AS dd_prev  ON dd_prev.sk_department = fcc.sk_prev_department
    LEFT JOIN dw_customer_support.dim_department AS dd_next  ON dd_next.sk_department = fcc.sk_next_department
    LEFT JOIN dw_customer_support.dim_analyst    AS da       ON da.sk_analyst = fcc.sk_analyst

    LEFT JOIN fact_service AS fs
           ON fcc.sk_support_session = fs.sk_support_session_varchar AND fs.rn_task = 1
 WHERE fcc.sk_support_session IN (SELECT sk_support_session FROM contacts_modified)
        AND   fcc.channel IN ('chat', 'call')
        AND fcc.is_interaction_answered = TRUE
),


satisfaction_ratings AS (
    SELECT DISTINCT 
        fa.sk_case,
        fa.sk_answer,
        sa.score_description,
        fa.satisfaction_score,
        fa.sk_ticket,
        fa.sk_support_session,
        CAST(fa.sk_ticket AS STRING) AS sk_ticket_varchar,
        COALESCE(NULLIF(fa.sk_support_session, '-1'), CAST(fa.sk_ticket AS STRING)) AS sk_support_session_fallback_ticket,
        fa.sk_survey,
        fa.secondary_satisfaction_score,
        COALESCE(rs.is_solved, rs_chat.is_solved) AS is_solved,
        da.respondent_comments AS csat_comment, 
        fa.ts_submitted,
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(
                NULLIF(CAST(fa.sk_support_session AS STRING), '-1'),
                CAST(fa.sk_ticket AS STRING)
            )
            ORDER BY fa.ts_submitted ASC
        ) AS rn
    
    FROM dw_satisfaction_rating.fact_answer AS fa
    LEFT JOIN ( -- Resolution Call
      SELECT DISTINCT
        COALESCE(NULLIF(fa.sk_support_session, '-1'), CAST(fa.sk_ticket AS STRING)) AS sk_support_session_fallback_ticket,
        fa.is_solved
      FROM dw_satisfaction_rating.fact_answer fa
      LEFT JOIN datalake_satisfaction_rating.satisfaction_answers sa 
        ON sa.id_answer = fa.sk_answer
      WHERE sa.score_description = 'resolution survey' 
        AND fa.is_solved IS NOT NULL
    ) rs ON COALESCE(NULLIF(fa.sk_support_session, '-1'), CAST(fa.sk_ticket AS STRING)) = rs.sk_support_session_fallback_ticket
    
    LEFT JOIN ( -- Resolution Chat
      SELECT DISTINCT
        COALESCE(NULLIF(fa.sk_support_session, '-1'), CAST(fa.sk_ticket AS STRING)) AS sk_support_session_fallback_ticket,
        fa.is_solved
      FROM dw_satisfaction_rating.fact_answer fa
      LEFT JOIN datalake_satisfaction_rating.satisfaction_answers sa 
        ON sa.id_answer = fa.sk_answer
      WHERE sa.secondary_score_description = 'resolution survey' 
        AND fa.is_solved IS NOT NULL
    ) rs_chat ON COALESCE(NULLIF(fa.sk_support_session, '-1'), CAST(fa.sk_ticket AS STRING)) = rs_chat.sk_support_session_fallback_ticket
          
    LEFT JOIN datalake_satisfaction_rating.satisfaction_answers sa 
      ON sa.id_answer = fa.sk_answer
    LEFT JOIN dw_satisfaction_rating.dim_answer da 
      ON fa.sk_answer = da.sk_answer 
    WHERE 1=1
      AND fa.ts_submitted >= CAST('2026-06-25' AS DATE)
      AND (
        (sa.service_context IN ('call','call inapp') AND sa.score_description = 'satisfaction evaluation') OR 
        (sa.service_context NOT IN ('call','call inapp'))
      )
),


last_contacts as (
SELECT DISTINCT
    cc.sk_support_session,
    cc.sk_task,
    COALESCE(tp.sk_user, cc.sk_user) as sk_user,
    cc.sk_ticket,
    COALESCE(NULLIF(cc.sk_support_session, '-1'), CAST(tp.sk_ticket AS STRING),
      CAST(cc.sk_ticket AS STRING) ) AS sk_support_session_fallback_ticket,
    cc.sk_analyst         AS sk_last_analyst,
    cc.area               AS last_area,
    cc.front_or_back,
    COALESCE(tp.last_team, cc.team)               AS last_team,
    cc.department         AS last_department,
    cc.transferred_from,
    cc.transferred_from_team,
    cc.transferred_to,
    cc.transferred_to_team,
    cc.status,
    COALESCE(tp.theme, cc.theme) as theme,
    COALESCE(tp.theme_detail, cc.theme_detail) as theme_detail,
    cc.agent_email,
    cc.agent_organization,
    CASE WHEN cc.agent_email LIKE '%webhelp%' THEN 'webhelp'
         WHEN cc.agent_email LIKE '%atento%' THEN 'atento'
         WHEN cc.agent_email LIKE '%aec%' THEN 'aec'
         WHEN cc.agent_email LIKE '%quintoandar%' THEN 'quintoandar'
         END as agent_organization_calc,
    cc.channel,
    cc.is_interaction_answered,
    cc.is_first_interaction,
    cc.is_last_interaction,
    cc.is_first_department_interaction,
    cc.is_spoc_task,
    cc.direction,
    COALESCE(tp.dt_created,cc.dt_created) as dt_created,
    cc.sk_session_key AS sk_session_key,
    cc.dt_created AS contact_dt_created,
    cc.ts_created AS contact_ts_created,
    COALESCE(ftc.first_csat_score, sa.satisfaction_score)                                  AS satisfaction_score,
    CASE
        WHEN COALESCE(ftc.first_csat_score, sa.satisfaction_score) IN (1, 2) THEN 1
        WHEN COALESCE(ftc.first_csat_score, sa.satisfaction_score) IS NOT NULL THEN 0
        ELSE NULL
    END                                                                                    AS is_detractor,
    CASE
        WHEN COALESCE(ftc.first_csat_score, sa.satisfaction_score) IN (4, 5) THEN 1
        WHEN COALESCE(ftc.first_csat_score, sa.satisfaction_score) IS NOT NULL THEN 0
        ELSE NULL
    END                                                                                    AS is_promoter,
    COALESCE(COALESCE(ftc.first_csat_score, sa.satisfaction_score) IS NOT NULL, FALSE)     AS has_satisfaction_response,
    COALESCE(ftc.ts_first_response, sa.ts_submitted)                                       AS ts_submitted,
    COALESCE(ftc.first_csat_comment,sa.csat_comment)                                      AS csat_comment,
    COALESCE(ftc.is_solved, sa.is_solved) as resolution_survey
FROM customer_contacts AS cc

LEFT JOIN (
      SELECT
        ftc.sk_ticket,
        ftc.first_csat_score,
        ftc.ts_first_response,
        ftc.is_solved,
        ftc.first_csat_comment
      FROM (
          SELECT *,
                 ROW_NUMBER() OVER (PARTITION BY sk_ticket ORDER BY ts_first_response DESC) as rnk
          FROM dw_satisfaction_rating.fact_ticket_csat
            WHERE sk_ticket IS NOT NULL
      ) ftc
      WHERE rnk = 1
  ) AS ftc ON ftc.sk_ticket = cc.sk_ticket AND cc.sk_ticket > 0
LEFT JOIN ( --fallback da fact_tickets
    SELECT
    ft.sk_ticket,
    dt.theme,
    dt.theme_detail,
    ft.sk_user,
    dd_last.team AS last_team,
    DATE(ft.ts_created) as dt_created,
    CASE WHEN dd_last.department = '[AeC] CX Pagamentos [FRONT] [POS]' THEN 'CX Pagamentos [FRONT] [POS]'
         WHEN dd_last.department = '[AeC] CX Rescisão [FRONT] [POS]' THEN 'CX Rescisão [FRONT] [POS]'
         WHEN dd_last.department = '[AeC] CX Mudança [FRONT] [POS]' THEN 'CX Mudança [FRONT] [POS]'
         WHEN dd_last.department = '[AeC] CX Reparos [FRONT] [POS]' THEN 'CX Reparos [FRONT] [POS]'
         WHEN dd_last.department = '[AeC] CX Ongoing [FRONT] [POS]' THEN 'CX Reparos [FRONT] [POS]'
         WHEN dd_last.department = '[AeC] CX Propostas [FRONT] [PRE]' THEN 'CX Propostas [FRONT] [PRE]'
         WHEN dd_last.department = '[AeC] CX Visitas [FRONT] [PRE]' THEN 'CX Visitas [FRONT] [PRE]'
         WHEN dd_last.department = '[AeC] CX Parceiros [FRONT] [PRE]' THEN 'CX Parceiros [FRONT] [PRE]'
         WHEN dd_last.department = '[AeC] Consultores imobiliários 5A' THEN 'Consultores imobiliários 5A'
         WHEN dd_last.department = '[AeC] CX Parceiros Compra e Venda [FRONT]' THEN 'CX Parceiros Compra e Venda [FRONT]'
         ELSE dd_last.department END AS last_department
FROM dw_customer_support.fact_tickets AS ft
LEFT JOIN dw_customer_support.dim_taxonomy AS dt
    ON dt.sk_taxonomy = ft.sk_taxonomy
LEFT JOIN dw_customer_support.dim_department AS dd_last
      ON dd_last.sk_department = ft.sk_main_department
WHERE
    ft.sk_ticket IS NOT NULL
) as tp ON tp.sk_ticket = cc.sk_ticket AND cc.sk_ticket > 0
LEFT JOIN satisfaction_ratings AS sa
    ON sa.sk_support_session_fallback_ticket = COALESCE(NULLIF(cc.sk_support_session, '-1'), CAST(tp.sk_ticket AS STRING), CAST(cc.sk_ticket AS STRING))
   AND sa.rn = 1 AND sa.sk_support_session_fallback_ticket != '-1'
   AND sa.ts_submitted >= DATE('2026-06-25')
WHERE cc.is_last_interaction = TRUE
),
recontact_drilldown_d4 AS (
SELECT
    tp.sk_support_session_fallback_ticket,
    date_sub(DATE(tp.dt_created), 3) AS recontact_search_window_from,
    DATE(tp.dt_created) AS recontact_search_window_until,
    
    LEAD(tp.sk_support_session_fallback_ticket) OVER (
        PARTITION BY tp.sk_user, tp.last_team, tp.theme
        ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
    ) AS recontact_sk_support_session_fallback_ticket,
    
    LEAD(tp.sk_task) OVER (
        PARTITION BY tp.sk_user, tp.last_team, tp.theme
        ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
    ) AS recontact_sk_task,
    
    LEAD(tp.dt_created) OVER (
        PARTITION BY tp.sk_user, tp.last_team, tp.theme
        ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
    ) AS recontact_ts_started,
    
    LEAD(tp.agent_email) OVER (
        PARTITION BY tp.sk_user, tp.last_team, tp.theme
        ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
    ) AS recontact_agent_email,
    
    LEAD(tp.agent_organization) OVER (
        PARTITION BY tp.sk_user, tp.last_team, tp.theme
        ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
    ) AS recontact_agent_organization,
    
    datediff(
        LEAD(DATE(tp.dt_created)) OVER (
            PARTITION BY tp.sk_user, tp.last_team, tp.theme
            ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
        ),
        DATE(tp.dt_created)
    ) AS recontact_interval_days,
    
    CAST((
        unix_timestamp(LEAD(tp.dt_created) OVER (
            PARTITION BY tp.sk_user, tp.last_team, tp.theme
            ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
        )) - unix_timestamp(tp.dt_created )
    ) / 3600 AS INT) AS recontact_interval_hours,
    
    CASE
        WHEN datediff(
                LEAD(DATE(tp.dt_created)) OVER (
                    PARTITION BY tp.sk_user, tp.last_team
                    ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
                ),
                DATE(tp.dt_created)
             ) <= 4
        THEN
            CASE
                WHEN tp.sk_support_session_fallback_ticket <> LEAD(tp.sk_support_session_fallback_ticket) OVER (
                        PARTITION BY tp.sk_user, tp.last_team
                        ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
                     )
                THEN 1 ELSE 0
            END
        ELSE 0
    END AS recontact_flag,
    
    CASE
        WHEN tp.theme IS NULL THEN 0
        WHEN datediff(
                LEAD(DATE(tp.dt_created)) OVER (
                    PARTITION BY tp.sk_user, tp.last_team, tp.theme
                    ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
                ),
                DATE(tp.dt_created)
             ) <= 4
        THEN
            CASE
                WHEN tp.sk_support_session_fallback_ticket <> LEAD(tp.sk_support_session_fallback_ticket) OVER (
                        PARTITION BY tp.sk_user, tp.last_team, tp.theme
                        ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
                     )
                THEN 1 ELSE 0
            END
        ELSE 0
    END AS theme_recontact_flag,
    
    CASE
        WHEN tp.theme IS NULL THEN 0
        WHEN datediff(
                LEAD(DATE(tp.dt_created)) OVER (
                    PARTITION BY tp.sk_user, tp.last_team, tp.theme
                    ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
                ),
                DATE(tp.dt_created)
             ) = 0
        THEN
            CASE
                WHEN tp.sk_support_session_fallback_ticket <> LEAD(tp.sk_support_session_fallback_ticket) OVER (
                        PARTITION BY tp.sk_user, tp.last_team, tp.theme
                        ORDER BY tp.dt_created, tp.sk_support_session_fallback_ticket
                     )
                THEN 1 ELSE 0
            END
        ELSE 0
    END AS theme_recontact_flag_D0
    
FROM last_contacts AS tp
WHERE 1 = 1
  AND tp.direction = 'inbound'
  AND tp.last_department NOT IN ('Welcome Onboarding [BACK] [POS]', 'CX Welcome Onboarding [FRONT][POS]')
  AND tp.channel IN ('call', 'chat', 'email')
  AND tp.sk_user IS NOT NULL
  AND tp.sk_user > 0
),


final_output AS (
    SELECT
        lc.sk_support_session,
        lc.sk_task,
        lc.sk_user,
        lc.sk_ticket,
        lc.sk_support_session_fallback_ticket,
        lc.sk_last_analyst,
        lc.last_area,
        lc.front_or_back,
        lc.last_team,
        lc.last_department,
        lc.transferred_from,
        lc.transferred_from_team,
        lc.transferred_to,
        lc.transferred_to_team,
        lc.status,
        lc.theme,
        lc.theme_detail,
        lc.agent_email,
        lc.agent_organization,
        lc.agent_organization_calc,
        lc.channel,
        lc.is_interaction_answered,
        lc.is_first_interaction,
        lc.is_last_interaction,
        lc.is_first_department_interaction,
        lc.is_spoc_task,
        lc.direction,
        lc.dt_created,
        lc.sk_session_key,
        lc.satisfaction_score,
        lc.is_detractor,
        lc.is_promoter,
        lc.has_satisfaction_response,
        lc.ts_submitted,
        lc.csat_comment,
        lc.resolution_survey,
        rd4.recontact_flag,
        rd4.theme_recontact_flag,
        rd4.theme_recontact_flag_d0,
        ROW_NUMBER() OVER (
            PARTITION BY lc.sk_support_session_fallback_ticket
            ORDER BY lc.contact_ts_created DESC, lc.sk_support_session DESC
        ) AS rn_merge_key
    FROM last_contacts lc
    LEFT JOIN recontact_drilldown_d4 AS rd4
        ON rd4.sk_support_session_fallback_ticket = lc.sk_support_session_fallback_ticket
        AND lc.sk_support_session_fallback_ticket IS NOT NULL
        AND lc.sk_support_session_fallback_ticket != '-1'
)
SELECT
    sk_support_session,
    sk_task,
    sk_user,
    sk_ticket,
    sk_support_session_fallback_ticket,
    sk_last_analyst,
    last_area,
    front_or_back,
    last_team,
    last_department,
    transferred_from,
    transferred_from_team,
    transferred_to,
    transferred_to_team,
    status,
    theme,
    theme_detail,
    agent_email,
    agent_organization,
    agent_organization_calc,
    channel,
    is_interaction_answered,
    is_first_interaction,
    is_last_interaction,
    is_first_department_interaction,
    is_spoc_task,
    direction,
    dt_created,
    sk_session_key,
    satisfaction_score,
    is_detractor,
    is_promoter,
    has_satisfaction_response,
    ts_submitted,
    csat_comment,
    resolution_survey,
    recontact_flag,
    theme_recontact_flag,
    theme_recontact_flag_d0,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day,
    NOW() AS ts_load
FROM final_output
WHERE rn_merge_key = 1
