WITH qac_user AS (
  SELECT 
    DATE(fdtof.dt_event) AS date,
    fdtof.sk_tof_user,
    MAX(COALESCE(fdtof.is_qac, False)) AS is_qac
  FROM 
    dw_growth.fact_demand_top_of_funnel_events AS fdtof
  WHERE
    DATE(fdtof.dt_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL
),
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
    CAST(NULL AS STRING) AS utm_content,
    fdtof.content_page,
    LOWER(fdtof.business_context) AS business_context,
    CAST(NULL AS STRING) AS sale_type,
    fdtof.funnel_side,
    fdtof.campaign_business_context,
    fdtof.behavior_type,
    fdtof.campaign_strategy_intent, 
    fdtof.medium, 
    fdtof.source,
    CAST(NULL AS BOOLEAN) AS is_cqa_demand,
    fdtof.year,
    fdtof.month,
    fdtof.day,
    qac_user.is_qac, -- QAC stands for "Quinto Andar Classifieds"
    COUNT(DISTINCT fdtof.sk_tof_user) AS tof_users, 
    COUNT(DISTINCT (CASE WHEN fdtof.is_rede_demand = TRUE THEN fdtof.sk_tof_user END)) AS tof_users_rede,
    COUNT(DISTINCT fdtof.sk_tof_event) AS tof_events, 
    COUNT(DISTINCT CASE WHEN fdtof.is_rede_demand = TRUE THEN fdtof.sk_tof_event END) AS tof_events_rede 
  FROM 
    dw_growth.fact_demand_top_of_funnel_events AS fdtof
  INNER JOIN 
    dw_public.dim_date AS dd 
      ON fdtof.dt_event = dd.date
  LEFT JOIN 
    dw_public.dim_region AS dr
      ON dr.sk_region = fdtof.sk_region
  LEFT JOIN
    qac_user
      ON qac_user.sk_tof_user = fdtof.sk_tof_user
        AND qac_user.date = dd.date
  WHERE 
    DATE(fdtof.dt_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL
), 
daily_prospect_metrics AS ( 
  SELECT
    dd.date, 
    dr.country_code, 
    dr.city_group, 
    fdpe.operation_channel, 
    IFNULL(fdpe.referral_type, 'NA') AS referral_type, 
    fdpe.platform,
    fdpe.utm_campaign, 
    fdpe.utm_term,
    fdpe.utm_content,
    fdpe.content_page,
    LOWER(fdpe.business_context) AS business_context,
    IFNULL(fdpe.sale_type, 'NA') AS sale_type,
    dms.funnel_side, 
    dms.campaign_business_context, 
    dms.campaign_strategy_intent, 
    dms.behavior_type, 
    dms.medium, 
    dms.source,
    IFNULL(fdpe.is_cqa_demand, FALSE) AS is_cqa_demand,
    fdpe.year,
    fdpe.month,
    fdpe.day,
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
    DATE(fdpe.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY ALL
)
SELECT
  COALESCE(t.date, p.date) AS dt_event,
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
  COALESCE(t.sale_type, p.sale_type) AS sale_type,
  COALESCE(t.funnel_side, p.funnel_side) AS funnel_side,
  COALESCE(t.campaign_business_context, p.campaign_business_context) AS campaign_business_context,
  COALESCE(t.behavior_type, p.behavior_type) AS behavior_type,
  COALESCE(t.campaign_strategy_intent, p.campaign_strategy_intent) AS campaign_strategy_intent,
  COALESCE(t.medium, p.medium) AS medium,
  COALESCE(t.source, p.source) AS source,
  COALESCE(t.is_cqa_demand, p.is_cqa_demand) AS is_cqa_demand,
  t.is_qac, -- We are deliberately not bringing this concept into "Prospects" for now.
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
  COALESCE(t.day, p.day) AS day,
  NOW() AS ts_load
FROM 
  daily_tof_metrics AS t 
  FULL OUTER JOIN daily_prospect_metrics AS p
    ON t.date = p.date
    AND t.city_group = p.city_group
    AND t.operation_channel = p.operation_channel
    AND t.referral_type = p.referral_type
    AND t.platform = p.platform
    AND t.utm_term = p.utm_term
    AND t.utm_content = p.utm_content
    AND t.content_page = p.content_page
    AND t.utm_campaign = p.utm_campaign
    AND t.business_context = p.business_context
    AND t.sale_type = p.sale_type
    AND t.funnel_side = p.funnel_side
    AND t.campaign_business_context = p.campaign_business_context
    AND t.behavior_type = p.behavior_type
    AND t.campaign_strategy_intent = p.campaign_strategy_intent
    AND t.medium = p.medium
    AND t.source = p.source
    AND t.is_cqa_demand = p.is_cqa_demand
