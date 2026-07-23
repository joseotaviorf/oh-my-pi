WITH historical_manual_costs AS (
    SELECT
    INT(REPLACE(dt_cost, '-', '')) AS id_date,
    'manual' AS flow_type,
    CAST(NULL AS STRING)  AS origin,
    CAST(NULL AS STRING) AS business_context,
    account_name,
    campaign_name,
    campaign_name AS utm_campaign,
    utm_term,
    utm_content,
    city_group AS city_group,
    country_code,
    campaign_business_context,
    campaign_strategy_intent,
    behavior_type,
    landing_page AS campaign_landing_page,
    medium,
    source,
    funnel_side,
    cost AS total_cost, 
    impressions, 
    clicks
    FROM
        datalake_growth_costs.historical_marketing_manual_costs
    WHERE
        DATE(dt_cost) >= DATE('2021-01-01') -- manual costs from before this date are included in historical partition
        AND cost != 0
        AND LOWER(SUBSTRING(NVL(campaign_name, ''), 1, 3)) <> 'dsa'        
),
historical_manual_costs_share_rules AS (
    SELECT
    INT(REPLACE(dt_cost, '-', '')) AS id_date,
    'manual' AS flow_type,
    CAST(NULL AS STRING) AS origin,
    CAST(NULL AS STRING) AS business_context,
    s.account_name,
    s.campaign_name,
    s.campaign_name AS utm_campaign,
    s.utm_term,
    s.utm_content,
    r.city_group AS city_group,
    r.country_code,
    s.campaign_business_context,
    s.campaign_strategy_intent,
    s.behavior_type,
    s.landing_page AS campaign_landing_page,
    s.medium,
    s.source,
    s.funnel_side,
    CAST(s.cost AS FLOAT) * r.share AS total_cost, 
    CAST(s.impressions AS FLOAT) AS impressions, 
    CAST(s.clicks AS FLOAT) AS clicks
    FROM
        datalake_growth_costs.historical_marketing_manual_costs_name_convention AS s
    JOIN
        datalake_growth_costs_sharing_rules.sharing_rules AS r 
            ON INT(REPLACE(dt_cost, '-', '')) = r.id_date
            AND s.id_rule = r.id_rule
            AND LOWER(s.funnel_side) = LOWER(r.funnel_side)
    WHERE
        DATE(dt_cost) >= DATE('2021-01-01') -- manual costs from before this date are included in historical partition
        AND CAST(s.cost AS FLOAT) * r.share != 0
        AND LOWER(SUBSTRING(NVL(s.campaign_name, ''), 1, 3)) <> 'dsa'
),
manual_costs AS (
    SELECT
    INT(REPLACE(dt_cost, '-', '')) AS id_date,
    'manual' AS flow_type,
    CAST(NULL AS STRING)  AS origin,
    CAST(NULL AS STRING) AS business_context,
    account_name,
    campaign_name,
    campaign_name AS utm_campaign,
    utm_term,
    utm_content,
    city_group AS city_group,
    country_code,
    campaign_business_context,
    campaign_strategy_intent,
    behavior_type,
    landing_page AS campaign_landing_page,
    medium,
    source,
    funnel_side,
    cost AS total_cost, 
    impressions, 
    clicks
    FROM
        datalake_gsheets_clean.marketing_manual_costs
    WHERE
        DATE(dt_cost) >= DATE('2021-01-01') -- manual costs from before this date are included in historical partition
        AND cost != 0
        AND LOWER(SUBSTRING(NVL(campaign_name, ''), 1, 3)) <> 'dsa'        
),
manual_costs_share_rules AS (
    SELECT
    INT(REPLACE(dt_cost, '-', '')) AS id_date,
    'manual' AS flow_type,
    CAST(NULL AS STRING) AS origin,
    CAST(NULL AS STRING) AS business_context,
    s.account_name,
    s.campaign_name,
    s.campaign_name AS utm_campaign,
    s.utm_term,
    s.utm_content,
    r.city_group AS city_group,
    r.country_code,
    s.campaign_business_context,
    s.campaign_strategy_intent,
    s.behavior_type,
    s.landing_page AS campaign_landing_page,
    s.medium,
    s.source,
    s.funnel_side,
    CAST(s.cost AS FLOAT) * r.share AS total_cost, 
    CAST(s.impressions AS FLOAT) AS impressions, 
    CAST(s.clicks AS FLOAT) AS clicks
    FROM
        datalake_gsheets_clean.marketing_manual_costs_name_convetion AS s
    JOIN
        datalake_growth_costs_sharing_rules.sharing_rules AS r 
            ON INT(REPLACE(dt_cost, '-', '')) = r.id_date
            AND s.id_rule = r.id_rule
            AND LOWER(s.funnel_side) = LOWER(r.funnel_side)
    WHERE
        DATE(dt_cost) >= DATE('2021-01-01') -- manual costs from before this date are included in historical partition
        AND CAST(s.cost AS FLOAT) * r.share != 0
        AND LOWER(SUBSTRING(NVL(s.campaign_name, ''), 1, 3)) <> 'dsa'
)

SELECT
  id_date,
  flow_type,
  origin,
  business_context,
  account_name,
  campaign_name,
  utm_campaign,
  utm_term,
  utm_content,
  city_group,
  country_code,
  campaign_business_context,
  campaign_strategy_intent,
  behavior_type,
  campaign_landing_page,
  medium,
  source,
  funnel_side,
  total_cost,
  impressions,
  clicks
FROM manual_costs
UNION ALL
SELECT
  id_date,
  flow_type,
  origin,
  business_context,
  account_name,
  campaign_name,
  utm_campaign,
  utm_term,
  utm_content,
  city_group,
  country_code,
  campaign_business_context,
  campaign_strategy_intent,
  behavior_type,
  campaign_landing_page,
  medium,
  source,
  funnel_side,
  total_cost,
  impressions,
  clicks
FROM manual_costs_share_rules
UNION ALL
SELECT
  id_date,
  flow_type,
  origin,
  business_context,
  account_name,
  campaign_name,
  utm_campaign,
  utm_term,
  utm_content,
  city_group,
  country_code,
  campaign_business_context,
  campaign_strategy_intent,
  behavior_type,
  campaign_landing_page,
  medium,
  source,
  funnel_side,
  total_cost,
  impressions,
  clicks
FROM historical_manual_costs
UNION ALL
SELECT
  id_date,
  flow_type,
  origin,
  business_context,
  account_name,
  campaign_name,
  utm_campaign,
  utm_term,
  utm_content,
  city_group,
  country_code,
  campaign_business_context,
  campaign_strategy_intent,
  behavior_type,
  campaign_landing_page,
  medium,
  source,
  funnel_side,
  total_cost,
  impressions,
  clicks
FROM historical_manual_costs_share_rules
