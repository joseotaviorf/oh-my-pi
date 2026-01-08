WITH segments_perspective AS (
  SELECT
    fcc.sk_interaction,
    fcc.sk_contact,
    fcc.sk_session,
    fcc.sk_task,
    fcc.sk_ticket,
    fcc.sk_user,
    fcc.channel,
    'INBOUND' AS refined_direction,
    fcc.origin as origin_fcc,
    CASE WHEN (ft.ticket_origin = 'n/a' or ft.ticket_origin is NULL) AND fcc.origin = 'in app' THEN CONCAT(fcc.channel,' in app')
         WHEN (ft.ticket_origin = 'n/a' or ft.ticket_origin is NULL) AND fcc.channel in ('call') THEN 'call inbound'
         WHEN ft.ticket_origin = 'n/a' THEN fcc.origin
      ELSE COALESCE(ft.ticket_origin, fcc.origin) END AS ticket_origin, 
    fcc.is_contact_answered as is_answered,
    fcc.is_interaction_answered,
    fcc.is_first_interaction,
    fcc.is_last_interaction,
    fcc.is_first_department_interaction,
    fcc.is_per_team_task AS per_team_flag,
    UPPER(fcc.status) as status,
    fcc.ts_reservation_created - INTERVAL 3 HOURS AS ts_reservation_created,
    NULL AS average_reply_time,
    fcc.total_handling_time,
    fcc.total_talk_time,      
    fcc.quinto_andar_phone_number,
    CASE
      WHEN fcc.sk_ticket IS NOT NULL THEN True
      WHEN fcc.sk_ticket > 0 THEN True 
      ELSE False 
    END AS has_ticket_created,
    dd.department,
    dd.team,
    dd.area,
    dd.front_or_back,
    dd.is_partner,
    dd.journey_step,
    dtax.customer_type_tag AS customer_type, 
    dtax.motivation,
    dtax.theme,
    dtax.theme_detail,
    dtax.journey,
    dtax.sub_journey,
    dtax.line_owner,
    da.email as agent_email,
    da.agent_organization,
    da.dt_agent_start AS agent_dt_start,
    FIRST_VALUE(da.email) OVER(PARTITION BY fcc.sk_ticket ORDER BY fcc.ts_reservation_created ASC) as first_agent_email,
    FIRST_VALUE(da.email) OVER(PARTITION BY fcc.sk_ticket ORDER BY fcc.ts_reservation_created DESC) as last_agent_email,
    ROW_NUMBER() OVER(PARTITION BY fcc.sk_contact ORDER BY fcc.ts_reservation_created) AS interaction_number,
    fcc.first_reply_time AS first_response_time,
    fcc.total_queue_time AS queue_time,
    fcc.total_talk_time AS talk_time,
    CASE 
      WHEN dd.team IN ('Visits','Propostas','Moving','CX Partners','CX Compra e Venda','CIQ') THEN 'Pré' 
      WHEN dd.team IN ('Repairs/Ongoing Front','Payments','Offboarding Front') THEN 'Pós'
      ELSE NULL 
    END AS front_pre_pos,
    dt.tags,
    dd_last.department AS last_department,
    dd_last.team AS last_team,
    dd_last.area AS last_area,
    dd_first.department AS first_department,
    dd_first.team AS first_team,
    dd_first.area AS first_area,
    dd_prev.department AS transferred_from,
    dd_prev.team AS transferred_from_team,
    dd_prev.area AS prev_area,
    dd_next.department AS transferred_to,
    dd_next.team AS transferred_to_team,
    dd_next.area AS next_area,
    fcc.ts_task_created - INTERVAL 3 HOURS as ts_created,
    DATE(fcc.ts_task_created - INTERVAL 3 HOURS) AS dt_created,
    ftc.first_csat_score,
    ftc.first_csat_comment,
    ftc.ts_first_response AS response_date,
    ftc.is_solved AS resolution_survey,
    fcc.is_spoc_task,
    fcc.direction as spoc_direction,
    REPLACE(get_json_object(custom_fields, '$."Session Source"'), '#', '') as session_source,
    fcc.sk_analyst,
    fii.step_name,
    fii.type as type_call,
    s.bot
  FROM
    dw_customer_support.fact_customer_contacts AS fcc
  LEFT JOIN
    dw_customer_support.fact_tickets AS ft
      ON ft.sk_ticket = fcc.sk_ticket
  LEFT JOIN 
    dw_customer_support.dim_department AS dd
      ON dd.sk_department = fcc.sk_department
  LEFT JOIN 
    dw_customer_support.dim_department AS dd_last
      ON dd_last.sk_department = ft.sk_main_department 
  LEFT JOIN 
    dw_customer_support.dim_department AS dd_first
      ON dd_first.sk_department = ft.sk_first_department 
  LEFT JOIN 
    dw_customer_support.dim_department AS dd_prev
      ON dd_prev.sk_department = fcc.sk_prev_department 
  LEFT JOIN 
    dw_customer_support.dim_department AS dd_next
      ON dd_next.sk_department = fcc.sk_next_department
  LEFT JOIN
    dw_customer_support.dim_ticket AS dt
      ON dt.sk_ticket = fcc.sk_ticket
  LEFT JOIN 
    dw_customer_support.dim_analyst AS da 
      ON da.sk_analyst = fcc.sk_analyst 
  LEFT JOIN
    dw_customer_support.dim_taxonomy AS dtax
      ON dtax.sk_taxonomy = dt.sk_taxonomy
  LEFT JOIN
    dw_satisfaction_rating.fact_ticket_csat AS ftc
      ON ftc.sk_ticket = fcc.sk_ticket
  LEFT JOIN
    dw_customer_support.fact_ivr_interactions as fii
      ON fcc.sk_interaction = fii.sk_interaction
  LEFT JOIN 
    datalake_chatbot.sessions s 
      ON CAST(fcc.sk_session AS STRING) = CAST(s.id_sauron_session AS STRING)
  WHERE 
    fcc.channel IN ('chat', 'call')
    AND fcc.origin NOT IN ('outbound')
    AND CAST(fcc.ts_task_created AS DATE) >= DATE('2025-01-01')
),
contacts AS (
  SELECT 
    sk_contact, 
    COUNT(sk_interaction) as vol_interaction 
  FROM dw_customer_support.fact_customer_contacts 
  WHERE CAST(ts_task_created AS DATE) >= DATE('2025-01-01') 
  GROUP BY 1 
),
analyst_start AS (
  SELECT 
    da.email as email, 
    min(ft.ts_created) as start_date
  FROM dw_customer_support.fact_tickets ft
  LEFT JOIN dw_customer_support.dim_analyst da 
    ON ft.sk_last_analyst = da.sk_analyst
  WHERE CAST(ft.ts_created AS DATE) >= DATE('2025-01-01')
  GROUP BY 1 
), 
first_resolution AS (
  SELECT 
    da.email as email, 
    min(ft.ts_solved) as first_resolution
  FROM dw_customer_support.fact_tickets ft
  LEFT JOIN dw_customer_support.dim_analyst da 
    ON ft.sk_last_analyst = da.sk_analyst
  WHERE CAST(ft.ts_created AS DATE) >= DATE('2025-01-01')
  GROUP BY 1 
)
SELECT 
  sp.sk_interaction,
  sp.sk_contact,
  sp.sk_session,
  sp.sk_task,
  sp.sk_ticket,
  sp.sk_user,
  sp.channel,
  sp.refined_direction,
  sp.origin_fcc,
  sp.ticket_origin, 
  sp.is_answered,
  sp.is_interaction_answered,
  sp.is_first_interaction,
  sp.is_last_interaction,
  sp.is_first_department_interaction,
  sp.per_team_flag,
  sp.status,
  sp.ts_reservation_created,
  NULL AS average_reply_time,
  sp.total_handling_time,
  sp.total_talk_time,      
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
  sp.agent_organization,
  sp.agent_dt_start,
  sp.first_agent_email,
  sp.last_agent_email,
  sp.interaction_number,
  sp.first_response_time,
  sp.queue_time,
  sp.talk_time,
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
  sp.prev_area,
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
  CASE 
    WHEN sp.status = 'TRANSFERRED'
      AND (
        transferred_to != last_department AND vol_interaction > 2
      ) THEN 'human_error' 
    WHEN sp.status = 'TRANSFERRED' THEN 'bot_error'
    ELSE 'no_transfer'
  END AS transfer_reason,
  CASE 
    WHEN is_last_interaction = TRUE 
    AND department != first_department THEN 'bot_error'
    WHEN is_last_interaction = FALSE 
    AND transferred_to != last_department 
    AND sp.status = 'TRANSFERRED' THEN 'human_error'
    WHEN is_last_interaction = FALSE 
    AND transferred_to = last_department 
    AND sp.status = 'TRANSFERRED' THEN 'department_correction'
  END AS transfer_reason_detailed,
  ast.start_date AS analyst_start_date,
  fr.first_resolution AS first_resouluiton_analyst,
  YEAR(sp.dt_created) AS year,
  MONTH(sp.dt_created) AS month,
  DAY(sp.dt_created) AS day,
  NOW() AS ts_load
FROM 
  segments_perspective AS sp
LEFT JOIN analyst_start AS ast
  ON sp.agent_email = ast.email
LEFT JOIN contacts AS c 
  ON c.sk_contact = sp.sk_contact
LEFT JOIN first_resolution AS fr
  ON sp.agent_email = fr.email
WHERE 
  DATE(sp.dt_created) BETWEEN DATE('{load_start_date}') - INTERVAL '1' YEAR AND DATE('{load_end_date}')
