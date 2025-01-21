WITH 
monthly_tof_metrics AS (
  SELECT
    dd.month_start,
    dr.country_code,
    dr.city_group, 
    fdtof.operation_channel,
    fdtof.platform,
    CAST(NULL AS STRING) AS referral_type, 
    CAST(NULL AS STRING) AS utm_campaign, 
    CAST(NULL AS STRING) AS utm_term,
    CAST(NULL AS STRING) AS utm_content,
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
    DATE(fdtof.dt_event) BETWEEN DATE_TRUNC('month', DATE_SUB(MAKE_DATE({year},{month},{day}), 14)) AND DATE(MAKE_DATE({year},{month},{day}))
  GROUP BY ALL

), 
monthly_prospect_metrics AS ( 
  SELECT
    dd.month_start, 
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
    COUNT(DISTINCT 
          CASE WHEN fdpe.event_name = 'USER FIRST ACTIVATION' THEN sk_prospect END) AS new_prospects, 
    COUNT(DISTINCT 
          CASE WHEN fdpe.event_name LIKE 'USER RECOVERY%' THEN sk_prospect END) AS recovered_prospects,    
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
    DATE(fdpe.ts_event) BETWEEN DATE_TRUNC('month', DATE_SUB(MAKE_DATE({year},{month},{day}), 14)) AND DATE(MAKE_DATE({year},{month},{day}))
  GROUP BY ALL
)
SELECT
  COALESCE(t.month_start, p.month_start) AS dt_month_start,
  COALESCE(t.country_code, p.country_code) AS country_code,
  COALESCE(t.city_group, p.city_group) AS city_group,
  COALESCE(t.operation_channel, p.operation_channel) AS operation_channel,
  COALESCE(t.referral_type, p.referral_type) AS referral_type,
  COALESCE(t.platform, p.platform) AS platform,
  COALESCE(t.utm_term, p.utm_term) AS utm_term,
  COALESCE(t.utm_content, p.utm_content) AS utm_content,
  COALESCE(t.content_page, p.content_page) AS content_page,
  COALESCE(t.utm_campaign, p.utm_campaign) AS utm_campaign,
  COALESCE(t.business_context, p.business_context) AS business_context,
  COALESCE(t.funnel_side, p.funnel_side) AS funnel_side,
  COALESCE(t.campaign_business_context, p.campaign_business_context) AS campaign_business_context,
  COALESCE(t.behavior_type, p.behavior_type) AS behavior_type,
  COALESCE(t.campaign_strategy_intent, p.campaign_strategy_intent) AS campaign_strategy_intent,
  COALESCE(t.medium, p.medium) AS medium,
  COALESCE(t.source, p.source) AS source,
  t.tof_users,
  t.tof_users_rede,
  t.tof_events,
  t.tof_events_rede,
  p.new_prospects,
  p.recovered_prospects,
  p.flows,
  CAST(NULL AS STRING) AS cost,
  COALESCE(t.year, p.year) AS year,
  COALESCE(t.month, p.month) AS month,
  1 AS day,
  NOW() AS ts_load
FROM 
  monthly_tof_metrics t 
  FULL OUTER JOIN monthly_prospect_metrics p
    ON t.month_start = p.month_start
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