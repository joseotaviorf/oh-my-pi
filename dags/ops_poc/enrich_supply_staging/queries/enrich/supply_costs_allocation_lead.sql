WITH dim_media_setup AS (
    SELECT 
        ms.id_media_setup AS sk_media_setup,
        ms.naming_convention_sufix,
        ms.campaign_business_context,
        ms.campaign_strategy_intent,
        ms.behavior_type,
        ms.campaign_landing_page,
        ms.medium,
        ms.source,
        ms.prefix_campaign_business_context,
        ms.prefix_campaign_strategy_intent,
        ms.prefix_behavior_type,
        ms.prefix_campaign_landing_page,
        ms.prefix_funnel_side,
        ms.prefix_medium,
        ms.prefix_source,
        ms.funnel_side,
        ms.ts_combination_created,
        ms.ts_load
    FROM 
        datalake_growth_taxonomy.media_setup AS ms
    QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY ms.naming_convention_sufix ORDER BY ms.ts_load DESC) = 1
),
leads AS (  
    SELECT 
        obt.date, 
        obt.city_group, 
        obt.nm_campaign,
        dms.naming_convention_sufix, 
        obt.company_report_origin,
        obt.planning_cluster,
        COUNT(distinct obt.sk_supply) leads,
        1 / CAST(SUM(COUNT(DISTINCT obt.sk_supply)) OVER (PARTITION BY obt.date, obt.nm_campaign) AS DOUBLE) AS leads_share
    FROM 
        dw_growth.obt_supply obt 
    JOIN 
        dw_growth.fact_supply_events fse 
            ON obt.sk_supply = fse.sk_supply
    LEFT JOIN 
        dim_media_setup AS dms
            ON fse.sk_media_setup = dms.sk_media_setup
    WHERE 
        obt.cd_funnel_step = 'lead'
        AND dms.naming_convention_sufix is not null
        AND obt.company_report_origin IN ('Owner PWA - Paid', 'Price Calculator - Sale', 'Price Calculator','Inbound')
        AND fse.sk_funnel_step = 5
    GROUP BY ALL
),
costs AS (
    SELECT
        dd.date as date,
        dr.city_group,
        mc.utm_campaign AS nm_campaign,
        mc.sk_campaign AS id_campaign,
        ms.naming_convention_sufix,
        ms.campaign_strategy_intent,
        ms.campaign_landing_page,
        ms.campaign_business_context,
        ms.source,
        ms.medium,
        ms.funnel_side,
        ms.behavior_type,
        SUM(total_cost) AS costs
    FROM 
        dw_growth.fact_media_platform_metrics mc 
    JOIN dw_public.dim_date dd 
        ON dd.sk_date = mc.sk_cost_date
    LEFT JOIN 
        dw_growth.dim_media_setup ms 
            ON ms.naming_convention_sufix = mc.naming_convention_sufix
    LEFT JOIN 
        dw_public.dim_region dr 
            ON dr.sk_region = mc.sk_region
    WHERE 
        ms.funnel_side = 'Supply'
    GROUP BY ALL
)
SELECT
    c.date,
    c.city_group,
    c.naming_convention_sufix,
    l.company_report_origin,
    l.planning_cluster,
    c.nm_campaign,
    c.id_campaign, 
    c.campaign_strategy_intent,
    c.campaign_landing_page,
    c.campaign_business_context,
    c.source,
    c.medium,
    c.funnel_side,
    c.behavior_type,
    c.costs * COALESCE((l.leads_share * l.leads),1) AS shared_cost
FROM 
    costs c 
LEFT JOIN 
    leads l
        ON c.date = l.date
        AND c.naming_convention_sufix = l.naming_convention_sufix
        AND c.nm_campaign = l.nm_campaign