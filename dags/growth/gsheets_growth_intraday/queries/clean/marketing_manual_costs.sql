SELECT
  NULLIF(account_name, '') AS account_name,
  NULLIF(campaign_name, '') AS campaign_name,
  NULLIF(ad_group_name, '') AS ad_group_name,
  NULLIF(utm_term, '') AS utm_term,
  NULLIF(utm_content, '') AS utm_content,
  NULLIF(funnel_side, '') AS funnel_side,
  NULLIF(country_code, '') AS country_code,
  NULLIF(city_group, '') AS city_group,
  NULLIF(campaign_strategy_intent, '') AS campaign_strategy_intent,
  NULLIF(behavior_type, '') AS behavior_type,
  NULLIF(medium, '') AS medium,
  NULLIF(source, '') AS source,
  NULLIF(campaign_business_context, '') AS campaign_business_context,
  NULLIF(landing_page, '') AS landing_page,
  CAST(REPLACE(NULLIF(cost, ''), ',', '') AS FLOAT) AS cost,
  CAST(REPLACE(NULLIF(impressions, ''), ',', '') AS FLOAT) AS impressions,
  CAST(REPLACE(NULLIF(clicks, ''), ',', '') AS FLOAT) AS clicks,
  CAST(NULLIF(dt, '') AS DATE) AS dt_cost
FROM
  datalake_gsheets_raw.marketing_manual_costs
