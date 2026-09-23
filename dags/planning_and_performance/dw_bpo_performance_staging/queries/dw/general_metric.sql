WITH  pp_multi as (
          SELECT
    dt_houses_owned as date,
    id_owner as sk_owner,
    ongoing_houses,
    is_pp_multi_active,
    CASE WHEN is_pp_multi_active = TRUE or ongoing_houses >= 5 THEN true ELSE false END AS is_pp_multi

    FROM datalake_pro_owners.daily_owner_houses_quantity_history ppm
    
    WHERE 
        (ongoing_houses >= 5 OR  is_pp_multi_active = TRUE)
        ),
-- EMR-safe replacement for `ON ft.sk_last_analyst = da.sk_analyst OR ft.sk_last_analyst = da.sk_agent_twilio`:
-- an OR join has no hash key, so Spark 3.5 plans it as a BroadcastNestedLoopJoin. UNION (not UNION ALL)
-- keeps one row per analyst matched by both keys, as the OR did.
analyst_by_key AS (
  SELECT
    sk_analyst AS sk_analyst_key,
    full_name,
    email,
    agent_organization
  FROM
    dw_customer_support.dim_analyst

  UNION

  SELECT
    sk_agent_twilio AS sk_analyst_key,
    full_name,
    email,
    agent_organization
  FROM
    dw_customer_support.dim_analyst
  WHERE
    sk_agent_twilio IS NOT NULL
)


SELECT DISTINCT
  ft.sk_ticket,
  ft.sk_user,
  ft.sk_last_analyst AS sk_agent,
  CASE
    WHEN ft.channel = 'cs email' THEN  'email'
    ELSE ft.channel
  END AS channel,
  ftc.first_csat_score AS csat_score,
  dit.status,
  CASE
    WHEN ftc.last_csat_score BETWEEN 4 AND 5 THEN 'Satisfied'
    WHEN ftc.last_csat_score = 3 THEN 'Neutral'
    WHEN ftc.last_csat_score BETWEEN 1 AND 2 THEN 'Dissatisfied'
    ELSE NULL
  END AS csat_type,
  ftc.first_csat_comment AS csat_comment,
  dd.department AS main_department,
  ft.direction,
  dd.area,
  dd.department,
  dd.journey_step,
  ft.front_or_back,
  dd.team,
  dt.motivation AS contact_motivation_tag,
  dt.theme AS contact_theme_tag,
  dt.theme_detail AS contact_theme_detail_tag,
  dt.customer_type_tag,
  dit.tags AS tag,
  dt.step_tag,
  CONCAT('https://quintoandar.zendesk.com/agent/tickets/', ft.sk_ticket) AS external_url,
  ROUND(CAST(ft.full_resolution_time_min_business/60.0 AS DOUBLE), 2) AS hours_to_solve_ticket,
  da.full_name AS agent_full_name,
  da.email AS agent_email,
  da.agent_organization AS organization,
  ft.reopens,
  ft.replies,
  dd.is_active,
  CASE
    WHEN ftc.sk_ticket IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS has_answered_csat,
  CAST(NULL AS BOOLEAN) AS has_transfers,
  ftc.is_solved AS is_resolution,
  ft.ts_created AS ts_started,
  ftc.ts_last_response AS ts_survey,
  ftc.ts_first_response AS ts_csat_response,
  ft.ts_solved,
  ft.ts_closed,
  YEAR(CURRENT_DATE) AS year,
  MONTH(CURRENT_DATE) AS month,
  DAY(CURRENT_DATE) AS day,
  NOW() AS ts_load,
  ft.requester_wait_time_min_business AS minutes_requester_wait_time_business,
  ft.reply_time_min_business AS minutes_first_reply_time_business,
  ft.full_resolution_time_min_business AS minutes_full_resolution_time_business,
  ppm.is_pp_multi
FROM
  dw_customer_support.fact_tickets AS ft
LEFT JOIN
  dw_satisfaction_rating.fact_ticket_csat AS ftc
    ON ftc.sk_ticket = ft.sk_ticket
LEFT JOIN
  dw_customer_support.dim_ticket AS dit
    ON dit.sk_ticket = ft.sk_ticket
LEFT JOIN
  dw_customer_support.dim_department AS dd
    ON ft.sk_main_department = dd.sk_department
LEFT JOIN
  dw_customer_support.dim_taxonomy AS dt
    ON ft.sk_taxonomy = dt.sk_taxonomy
LEFT JOIN
  analyst_by_key AS da
    ON ft.sk_last_analyst = da.sk_analyst_key
LEFT JOIN pp_multi AS ppm 
    ON ppm.sk_owner = ft.sk_user  
    AND date(ppm.date) = date(ft.ts_created)    
WHERE
  DATE(ft.ts_created) BETWEEN DATE('{load_start_date}') - INTERVAL '1' YEAR AND DATE('{load_end_date}')
