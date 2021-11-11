-- Union of medias
WITH medias_consolidated AS (
    -- GOOGLE
    SELECT
        id_date,
        'google' AS origin,
        campaign_name,
        campaign_city,
        account_name,
        report_type,
        ad_type,
        utm_term,
        utm_content,
        utm_campaign,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost
    FROM
        datalake_consolidated_marketing_costs.google_consolidated_costs
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    -- CRITEO
    UNION ALL
    SELECT
        id_date,
        'criteo' AS origin,
        campaign_name,
        NULL AS campaign_city,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        0.0 AS desktop_cost,
        0.0 AS mobile_cost,
        other_cost,
        total_cost
    FROM
        datalake_consolidated_marketing_costs.criteo_consolidated_costs
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    -- RTB
    UNION ALL
    SELECT
        id_date,
        'rtb' AS origin,
        campaign_name,
        NULL AS campaign_city,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        0.0 AS desktop_cost,
        0.0 AS mobile_cost,
        other_cost,
        total_cost
    FROM
        datalake_consolidated_marketing_costs.rtb_consolidated_costs
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    -- MITULA
    UNION ALL
    SELECT
        id_date,
        'mitula' AS origin,
        campaign_name,
        NULL AS campaign_city,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost
    FROM
        datalake_consolidated_marketing_costs.mitula_consolidated_costs
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    -- TROVIT
    UNION ALL
    SELECT
        id_date,
        'trovit' AS origin,
        campaign_name,
        NULL AS campaign_city,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost
    FROM
        datalake_consolidated_marketing_costs.trovit_consolidated_costs
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    -- FACEBOOK
    UNION ALL
    SELECT
        id_date,
        'facebook' AS origin,
        campaign_name,
        campaign_city,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        utm_term,
        utm_content,
        utm_campaign,
        desktop_cost,
        mobile_cost,
        other_cost,
        total_cost
    FROM
        datalake_consolidated_marketing_costs.facebook_consolidated_costs
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
),

shared_consolidated_costs AS (
    SELECT
        mc.id_date,
        origin,
        campaign_name,
        campaign_city,
        sr.city_group as sharing_rules_city_group,
        account_name,
        utm_campaign,
        utm_term,
        utm_content,
        desktop_cost * COALESCE(sr.share, 1) AS desktop_cost,
        mobile_cost * COALESCE(sr.share, 1) AS mobile_cost,
        other_cost * COALESCE(sr.share, 1) AS other_cost,
        total_cost * COALESCE(sr.share, 1) AS total_cost,
        report_type,
        ad_type
    FROM
        medias_consolidated mc
        LEFT JOIN datalake_marketing_costs_sharing_rules.old_sharing_rules sr
            ON mc.id_date = sr.id_date 
            AND split(mc.campaign_name, '\\\\.')[0] = sr.id_rule
),

-- Next CTE is going to be deprecated soon
-- For more information access
-- https://docs.google.com/presentation/d/1YnqR-ypPI58I_Q1Re3VljXQqlP6XlUzfcvInxFFlUZw/edit#slide=id.gcd7c7ea5b9_0_0

city_group_mappings AS (
    SELECT DISTINCT
        mc.campaign_name,
        cgoch.city_group AS city_group_old_campaigns,
        dr.city_group AS city_group_by_sk_region
    FROM
        medias_consolidated mc
        LEFT JOIN datalake_consolidated_marketing_costs.city_group_old_campaigns_historic cgoch
            ON mc.sk_date = cgoch.sk_date
                AND LOWER(mc.campaign_name) = LOWER(cgoch.campaign_name)
        LEFT JOIN datalake_region.region dr
            ON split(mc.campaign_name, '\\\\.')[0] = dr.id
                AND mc.id_date >= 20210705
)

SELECT 
    id_date,
    origin,
    scc.campaign_name,
    COALESCE(
        cgm.city_group_old_campaigns,
        scc.sharing_rules_city_group,        
        cgm.city_group_by_sk_region,
        'Not Mapped'
    ) AS city_group,
    account_name,
    utm_campaign,
    utm_term,
    utm_content,
    desktop_cost,
    mobile_cost,
    other_cost,
    total_cost,
    report_type,
    ad_type
FROM 
    shared_consolidated_costs scc
    LEFT JOIN city_group_mappings cgm
      ON scc.campaign_name = cgm.campaign_name
