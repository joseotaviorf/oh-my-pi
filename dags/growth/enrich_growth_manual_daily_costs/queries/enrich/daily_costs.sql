WITH
manual_costs AS (
    SELECT
    REPLACE(dt_cost, '-', '')::INT AS id_date,
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
    REPLACE(dt_cost, '-', '')::INT AS id_date,
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
    s.cost::FLOAT * r.share AS total_cost, 
    s.impressions::FLOAT AS impressions, 
    s.clicks::FLOAT AS clicks
    FROM
        datalake_gsheets_clean.marketing_manual_costs_name_convetion AS s
    JOIN
        datalake_growth_costs_sharing_rules.sharing_rules AS r 
            ON INT(REPLACE(dt_cost, '-', '')) = r.id_date
            AND s.id_rule = r.id_rule
            AND LOWER(s.funnel_side) = LOWER(r.funnel_side)
    WHERE
        DATE(dt_cost) >= DATE('2021-01-01') -- manual costs from before this date are included in historical partition
        AND s.cost::FLOAT * r.share != 0
        AND LOWER(SUBSTRING(NVL(s.campaign_name, ''), 1, 3)) <> 'dsa'
)
SELECT *
FROM manual_costs
UNION ALL
SELECT *
FROM manual_costs_share_rules
