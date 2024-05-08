WITH 
daily_tof_metrics AS (
  SELECT
    dd.date,
    dr.country_code,
    dr.city_group, 
    fdtof.operation_channel,
    fdtof.platform,
    CAST(NULL AS STRING) AS referral_type, 
    CAST(NULL AS STRING) AS utm_campaign, 
    CAST(NULL AS STRING) AS utm_term, 
    LOWER(fdtof.business_context) AS business_context,
    fdtof.funnel_side,
    fdtof.campaign_business_context,
    fdtof.behavior_type,
    fdtof.campaign_strategy_intent, 
    fdtof.medium, 
    fdtof.source,
    fdtof.year,
    fdtof.month,
    fdtof.day,
    COUNT(DISTINCT fdtof.sk_tof_user) AS tof_users, 
    COUNT(DISTINCT (CASE WHEN fdtof.is_rede_demand = TRUE THEN fdtof.sk_tof_user END)) AS tof_users_rede,
    COUNT(DISTINCT fdtof.sk_tof_event) AS tof_events, 
    COUNT(DISTINCT CASE WHEN fdtof.is_rede_demand = TRUE THEN fdtof.sk_tof_event END) AS tof_events_rede 
  FROM 
    dw_growth.fact_demand_top_of_funnel_events AS fdtof
    INNER JOIN dw_public.dim_date AS dd 
        ON fdtof.dt_event = dd.date
    LEFT JOIN dw_public.dim_region AS dr
        ON dr.sk_region = fdtof.sk_region
  WHERE 
    fdtof.year = {year}
    AND fdtof.month = {month}
    AND fdtof.day = {day}
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18

), 
daily_prospect_metrics AS ( 
  SELECT
    dd.date, 
    dr.country_code, 
    dr.city_group, 
    fdpe.operation_channel, 
    fdpe.referral_type, 
    fdpe.platform,
    fdpe.utm_campaign, 
    fdpe.utm_term,  
    LOWER(fdpe.business_context) AS business_context, 
    dms.funnel_side, 
    dms.campaign_business_context, 
    dms.campaign_strategy_intent, 
    dms.behavior_type, 
    dms.medium, 
    dms.source,
    fdpe.year,
    fdpe.month,
    fdpe.day,
    COUNT(DISTINCT 
          CASE WHEN fdpe.event_name = 'USER FIRST ACTIVATION' THEN sk_prospect END) AS new_prospects, 
    COUNT(DISTINCT 
          CASE WHEN fdpe.event_name = 'USER RECOVERY' THEN sk_prospect END) AS recovered_prospects,    
    COUNT(DISTINCT 
          CASE WHEN fdpe.event_type = 'FLOW' AND flow_order = 1 THEN sk_flow END) AS flows 
  FROM 
    dw_growth.fact_demand_prospect_events  AS fdpe
    INNER JOIN dw_public.dim_date AS dd 
      ON dd.sk_date = fdpe.sk_event_date 
    LEFT JOIN dw_growth.dim_media_setup AS dms 
      ON fdpe.naming_convention_sufix = dms.naming_convention_sufix 
    LEFT JOIN dw_public.dim_region AS dr
      ON fdpe.sk_region = dr.sk_region
  WHERE 
    fdpe.year = {year}
    AND fdpe.month = {month}
    AND fdpe.day = {day}
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18
), 
daily_costs_metrics AS ( 
  SELECT
    dd.date, 
    dc.country_code, 
    dc.city_group, 
    NULL AS operation_channel, 
    NULL AS referral_type, 
    NULL AS platform, 
    dc.campaign_name AS utm_campaign,
    dc.utm_term, 
    LOWER(dc.business_context) AS business_context,
    dc.funnel_side, 
    dc.campaign_business_context, 
    dc.campaign_strategy_intent, 
    dc.behavior_type, 
    dc.medium, 
    dc.source,
    dd.year,
    dd.month,
    dd.day,
    SUM(dc.total_cost) AS cost
  FROM 
    datalake_growth_costs.daily_costs AS dc
    INNER JOIN dw_public.dim_date AS dd 
      ON dd.sk_date = dc.id_date
  WHERE 
    dd.year = {year}
    AND dd.month = {month}
    AND dd.day = {day}
    AND LOWER(funnel_side) IN ('demand', 'branding')
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18  
)
SELECT
  COALESCE(t.date, p.date, c.date) AS dt_event,
  COALESCE(t.country_code, p.country_code, c.country_code) AS country_code,
  COALESCE(t.city_group, p.city_group, c.city_group) AS city_group,
  COALESCE(t.operation_channel, p.operation_channel, c.operation_channel) AS operation_channel,
  COALESCE(t.referral_type, p.referral_type, c.referral_type) AS referral_type,
  COALESCE(t.platform, p.platform, c.platform) AS platform,
  COALESCE(t.utm_term, p.utm_term, c.utm_term) AS utm_term,
  COALESCE(t.utm_campaign, p.utm_campaign, c.utm_campaign) AS utm_campaign,
  COALESCE(t.business_context, p.business_context, c.business_context) AS business_context,
  COALESCE(t.funnel_side, p.funnel_side, c.funnel_side) AS funnel_side,
  COALESCE(t.campaign_business_context, p.campaign_business_context, c.campaign_business_context) AS campaign_business_context,
  COALESCE(t.behavior_type, p.behavior_type, c.behavior_type) AS behavior_type,
  COALESCE(t.campaign_strategy_intent, p.campaign_strategy_intent, c.campaign_strategy_intent) AS campaign_strategy_intent,
  COALESCE(t.medium, p.medium, c.medium) AS medium,
  COALESCE(t.source, p.source, c.source) AS source,
  t.tof_users,
  t.tof_users_rede,
  t.tof_events,
  t.tof_events_rede,
  p.new_prospects,
  p.recovered_prospects,
  p.flows,
  c.cost,
  COALESCE(t.year, p.year, c.year) AS year,
  COALESCE(t.month, p.month, c.month) AS month,
  COALESCE(t.day, p.day, c.day) AS day,
  NOW() AS ts_load
FROM 
  daily_tof_metrics t 
  FULL OUTER JOIN daily_prospect_metrics p
    ON t.date = p.date
    AND t.city_group = p.city_group
    AND t.operation_channel = p.operation_channel
    AND t.referral_type = p.referral_type
    AND t.platform = p.platform
    AND t.utm_term = p.utm_term
    AND t.utm_campaign = p.utm_campaign
    AND t.business_context = p.business_context
    AND t.funnel_side = p.funnel_side
    AND t.campaign_business_context = p.campaign_business_context
    AND t.behavior_type = p.behavior_type
    AND t.campaign_strategy_intent = p.campaign_strategy_intent
    AND t.medium = p.medium
    AND t.source = p.source
  FULL OUTER JOIN daily_costs_metrics c
    ON t.date = c.date
    AND t.city_group = c.city_group
    AND t.operation_channel = c.operation_channel
    AND t.referral_type = c.referral_type
    AND t.platform = c.platform
    AND t.utm_term = c.utm_term
    AND t.utm_campaign = c.utm_campaign
    AND t.business_context = c.business_context
    AND t.funnel_side = c.funnel_side
    AND t.campaign_business_context = c.campaign_business_context
    AND t.behavior_type = c.behavior_type
    AND t.campaign_strategy_intent = c.campaign_strategy_intent
    AND t.medium = c.medium
    AND t.source = c.source