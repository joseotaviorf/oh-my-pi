WITH historical_manual_costs AS (
    SELECT
    NULL AS bk_sharing_rules,
    NULL AS id_rule,
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
    clicks,
    dt_cost
    FROM
        datalake_growth_costs.historical_marketing_manual_costs
    WHERE
        DATE(dt_cost) >= DATE('2021-01-01') -- manual costs from before this date are included in historical partition
        AND cost != 0
        AND LOWER(SUBSTRING(NVL(campaign_name, ''), 1, 3)) <> 'dsa'        
),
historical_manual_costs_share_rules AS (
    SELECT
    MD5(CONCAT(CAST(REPLACE(dt_cost, '-', '') AS STRING), '_', id_rule, funnel_side)) AS bk_sharing_rules,
    id_rule,
    s.account_name,
    s.campaign_name,
    s.campaign_name AS utm_campaign,
    s.utm_term,
    s.utm_content,
    NULL AS city_group,
    NULL AS country_code,
    s.campaign_business_context,
    s.campaign_strategy_intent,
    s.behavior_type,
    s.landing_page AS campaign_landing_page,
    s.medium,
    s.source,
    s.funnel_side,
    s.cost::FLOAT AS total_cost, 
    s.impressions::FLOAT AS impressions, 
    s.clicks::FLOAT AS clicks,
    s.dt_cost
    FROM
        datalake_growth_costs.historical_marketing_manual_costs_name_convention AS s
    WHERE
        DATE(dt_cost) >= DATE('2021-01-01') -- manual costs from before this date are included in historical partition
        AND s.cost != 0
        AND LOWER(SUBSTRING(NVL(s.campaign_name, ''), 1, 3)) <> 'dsa'
),
manual_costs AS (
SELECT
    NULL AS bk_sharing_rules,
    NULL AS id_rule,
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
    clicks,
    dt_cost
    FROM
        datalake_gsheets_clean.marketing_manual_costs
    WHERE
        DATE(dt_cost) >= DATE('2021-01-01') -- manual costs from before this date are included in historical partition
        AND cost != 0
        AND LOWER(SUBSTRING(NVL(campaign_name, ''), 1, 3)) <> 'dsa'        
),
manual_costs_share_rules AS (
    SELECT
    MD5(CONCAT(CAST(REPLACE(dt_cost, '-', '') AS STRING), '_', id_rule, funnel_side)) AS bk_sharing_rules,
    id_rule,
    s.account_name,
    s.campaign_name,
    s.campaign_name AS utm_campaign,
    s.utm_term,
    s.utm_content,
    NULL AS city_group,
    NULL AS country_code,
    s.campaign_business_context,
    s.campaign_strategy_intent,
    s.behavior_type,
    s.landing_page AS campaign_landing_page,
    s.medium,
    s.source,
    s.funnel_side,
    s.cost::FLOAT AS total_cost, 
    s.impressions::FLOAT AS impressions, 
    s.clicks::FLOAT AS clicks,
    s.dt_cost
    FROM
        datalake_gsheets_clean.marketing_manual_costs_name_convetion AS s
    WHERE
        DATE(dt_cost) >= DATE('2021-01-01') -- manual costs from before this date are included in historical partition
        AND s.cost != 0
        AND LOWER(SUBSTRING(NVL(s.campaign_name, ''), 1, 3)) <> 'dsa'
),
base_manual_costs AS (
SELECT *
FROM manual_costs
UNION ALL
SELECT *
FROM manual_costs_share_rules
UNION ALL
SELECT *
FROM historical_manual_costs
UNION ALL
SELECT *
FROM historical_manual_costs_share_rules
),
region as (
    SELECT 
        id AS id_region,
        city_group
    FROM 
        datalake_region.region
    QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY city_group ORDER BY id) = 1
)
SELECT
    bk_sharing_rules,
    id_rule,
    r.id_region,
    CONCAT_WS(".",
      LOWER(LEFT(campaign_business_context,4)),
      LOWER(LEFT(campaign_strategy_intent,3)),
      LOWER(COALESCE(LEFT(SPLIT(behavior_type, " ")[0],3) ||LEFT(SPLIT(behavior_type, " ")[1],3), LEFT(behavior_type, 3))),
      LOWER(COALESCE(LEFT(SPLIT(campaign_landing_page, " ")[0],3) ||LEFT(SPLIT(campaign_landing_page, " ")[1],3), LEFT(campaign_landing_page, 3))),
      LOWER(LEFT(funnel_side,1)),
      LOWER(LEFT(REPLACE(medium, ' ', ''), 20)),
      LOWER(LEFT(REPLACE(source, ' ', ''), 20))
  ) AS naming_convention_sufix,
    account_name,
    utm_campaign,
    utm_term,
    utm_content,
    campaign_business_context,
    campaign_strategy_intent,
    campaign_landing_page,
    behavior_type,
    medium,
    source,
    funnel_side,
    total_cost,
    impressions,
    clicks,
    dt_cost,
    YEAR(dt_cost) as year,
    MONTH(dt_cost) as month,
    DAY(dt_cost) as day
FROM 
    base_manual_costs bmc 
LEFT JOIN region r 
    ON bmc.city_group = r.city_group
WHERE source not in ('Google', 'Facebook', 'Criteo')    
