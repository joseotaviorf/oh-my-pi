WITH 
weekly_tof_metrics AS (
  SELECT
    dd.week_start,
    dr.country_code,
    dr.city_group, 
    fdtof.operation_channel,
    fdtof.platform,
    CAST(NULL AS STRING) AS referral_type, 
    CAST(NULL AS STRING) AS utm_campaign, 
    CAST(NULL AS STRING) AS utm_term,
    fdtof.utm_content,
    fdtof.content_page,
    LOWER(fdtof.business_context) AS business_context,
    fdtof.funnel_side,
    fdtof.campaign_business_context,
    fdtof.behavior_type,
    fdtof.campaign_strategy_intent, 
    fdtof.medium, 
    fdtof.source,
    fdtof.year,
    fdtof.month,
    EXTRACT(DAY FROM DATE_TRUNC('week', dd.week_start)) AS day,
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
    DATE(fdtof.dt_event) BETWEEN DATE_TRUNC('week', DATE_SUB(MAKE_DATE({year},{month},{day}), 14)) AND DATE(MAKE_DATE({year},{month},{day}))
  GROUP BY ALL

), 
weekly_prospect_metrics AS ( 
  SELECT
    dd.week_start, 
    dr.country_code, 
    dr.city_group, 
    fdpe.operation_channel, 
    fdpe.referral_type, 
    fdpe.platform,
    fdpe.utm_campaign, 
    fdpe.utm_term,
    fdpe.utm_content,
    fdpe.content_page,
    LOWER(fdpe.business_context) AS business_context, 
    dms.funnel_side, 
    dms.campaign_business_context, 
    dms.campaign_strategy_intent, 
    dms.behavior_type, 
    dms.medium, 
    dms.source,
    fdpe.year,
    fdpe.month,
    EXTRACT(DAY FROM DATE_TRUNC('week', dd.week_start)) AS day,
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
    DATE(fdpe.ts_event) BETWEEN DATE_TRUNC('week', DATE_SUB(MAKE_DATE({year},{month},{day}), 14)) AND DATE(MAKE_DATE({year},{month},{day}))
  GROUP BY ALL
), 
weekly_costs_metrics AS ( 
  SELECT 
    dd.week_start, 
    dc.country_code, 
    dc.city_group, 
    NULL AS operation_channel, 
    NULL AS referral_type, 
    NULL AS platform, 
    dc.campaign_name AS utm_campaign,
    dc.utm_term,
    dc.utm_content,
    CAST(NULL AS STRING) AS content_page,
    LOWER(dc.business_context) AS business_context,
    dc.funnel_side, 
    dc.campaign_business_context, 
    dc.campaign_strategy_intent, 
    dc.behavior_type, 
    dc.medium, 
    dc.source,
    dd.year,
    dd.month,
    EXTRACT(DAY FROM DATE_TRUNC('week', dd.week_start)) AS day,
    SUM(dc.total_cost) AS cost
  FROM 
    datalake_growth_costs.daily_costs AS dc
    INNER JOIN dw_public.dim_date AS dd 
      ON dd.sk_date = dc.id_date
  WHERE 
    DATE(dd.date) BETWEEN DATE_TRUNC('week', DATE_SUB(MAKE_DATE({year},{month},{day}), 14)) AND DATE(MAKE_DATE({year},{month},{day}))
    AND LOWER(funnel_side) IN ('demand', 'branding')
  GROUP BY ALL
)
SELECT
  COALESCE(t.week_start, p.week_start, c.week_start) AS dt_week_start,
  COALESCE(t.country_code, p.country_code, c.country_code) AS country_code,
  COALESCE(t.city_group, p.city_group, c.city_group) AS city_group,
  COALESCE(t.operation_channel, p.operation_channel, c.operation_channel) AS operation_channel,
  COALESCE(t.referral_type, p.referral_type, c.referral_type) AS referral_type,
  COALESCE(t.platform, p.platform, c.platform) AS platform,
  COALESCE(t.utm_term, p.utm_term, c.utm_term) AS utm_term,
  COALESCE(t.utm_content, p.utm_content, c.utm_content) AS utm_content,
  COALESCE(t.content_page, p.content_page, c.content_page) AS content_page,
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
  weekly_tof_metrics t 
  FULL OUTER JOIN weekly_prospect_metrics p
    ON t.week_start = p.week_start
    AND t.city_group = p.city_group
    AND t.operation_channel = p.operation_channel
    AND t.referral_type = p.referral_type
    AND t.platform = p.platform
    AND t.utm_term = p.utm_term
    AND t.utm_content = p.utm_content
    AND t.content_page = p.content_page
    AND t.utm_campaign = p.utm_campaign
    AND t.business_context = p.business_context
    AND t.funnel_side = p.funnel_side
    AND t.campaign_business_context = p.campaign_business_context
    AND t.behavior_type = p.behavior_type
    AND t.campaign_strategy_intent = p.campaign_strategy_intent
    AND t.medium = p.medium
    AND t.source = p.source
  FULL OUTER JOIN weekly_costs_metrics c
    ON t.week_start = c.week_start
    AND t.city_group = c.city_group
    AND t.operation_channel = c.operation_channel
    AND t.referral_type = c.referral_type
    AND t.platform = c.platform
    AND t.utm_term = c.utm_term
    AND t.utm_content = c.utm_content
    AND t.content_page = c.content_page
    AND t.utm_campaign = c.utm_campaign
    AND t.business_context = c.business_context
    AND t.funnel_side = c.funnel_side
    AND t.campaign_business_context = c.campaign_business_context
    AND t.behavior_type = c.behavior_type
    AND t.campaign_strategy_intent = c.campaign_strategy_intent
    AND t.medium = c.medium
    AND t.source = c.source
