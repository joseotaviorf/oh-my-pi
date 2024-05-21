WITH
costs_targets_results_combined AS (
    ---------------------------------
        -- Supply ToF Volumes Sale --
    ---------------------------------
    SELECT 
        CAST(DATE_FORMAT(dt_event, 'yyyyMMdd') as BIGINT) AS sk_date,
        COALESCE(city_group, 'Not Mapped') AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        COALESCE(mkt_origin,'') AS mkt_origin,
        COALESCE(mkt_channel,'') AS mkt_channel,
        COALESCE(mkt_medium,'') AS mkt_medium,
        COALESCE(mkt_source,'') AS mkt_source,
        COALESCE(utm_campaign,'') AS utm_campaign,
        COALESCE(utm_content,'') AS utm_content,
        COALESCE(utm_term,'') AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(traffic) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
        SUM(CAST(0 AS FLOAT)) AS budget_sale,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,       
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
        SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM 
        datalake_top_of_funnel_supply.top_of_funnel_supply
    WHERE 
        mkt_origin IN ('Owner PWA - Sale', 'Price Calculator - Sale')
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11
        
    UNION ALL

    ---------------------------------
        -- Supply ToF Volumes Rent --
    ---------------------------------
    SELECT 
        CAST(DATE_FORMAT(dt_event, 'yyyyMMdd') as BIGINT) AS sk_date,
        COALESCE(city_group, 'Not Mapped') AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        COALESCE(mkt_origin,'') AS mkt_origin,
        COALESCE(mkt_channel,'') AS mkt_channel,
        COALESCE(mkt_medium,'') AS mkt_medium,
        COALESCE(mkt_source,'') AS mkt_source,
        COALESCE(utm_campaign,'') AS utm_campaign,
        COALESCE(utm_content,'') AS utm_content,
        COALESCE(utm_term,'') AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(traffic) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid, 
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
        SUM(CAST(0 AS FLOAT)) AS budget_sale,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
        SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM 
        datalake_top_of_funnel_supply.top_of_funnel_supply
    WHERE 
        mkt_origin NOT IN ('Owner PWA - Sale', 'Price Calculator - Sale')
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11
        
    UNION ALL

    ---------------------------------
        -- Supply ToF Targets --
    ---------------------------------
    SELECT 
        CAST(DATE_FORMAT(dt_target, 'yyyyMMdd') as BIGINT) AS sk_date,
        COALESCE(city_group, 'Not Mapped') AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        COALESCE(supply_origin,'') AS mkt_origin,
        COALESCE(supply_channel,'') AS mkt_channel,
        COALESCE(supply_medium,'') AS mkt_medium,
        COALESCE(supply_source,'') AS mkt_source,
        CAST(NULL AS STRING) AS  utm_campaign,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(traffic) AS tof_target,       
        SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
        SUM(CAST(0 AS FLOAT)) AS budget_sale,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
        SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM 
        datalake_gsheets_clean.tof_supply_targets
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL

    ---------------------------------
        -- Supply Leads Volume --
    ---------------------------------
    SELECT
		f.sk_lead_date AS sk_date,
		COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        ac.affiliate_volumetry,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Partners'
            ELSE COALESCE(f.mkt_origin,'')
        END AS mkt_origin,
        COALESCE(f.mkt_channel,'') AS mkt_channel,
        COALESCE(f.mkt_medium,'') AS mkt_medium,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Spinver'
            ELSE COALESCE(f.mkt_source,'')
        END AS mkt_source,
		COALESCE(dl.utm_campaign,'') AS utm_campaign,
		COALESCE(dl.utm_content,'') AS utm_content,
		COALESCE(dl.utm_term,'') AS utm_term,
		COALESCE(p.origin_phone,'') AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
		COUNT(DISTINCT CASE WHEN sk_lead_date > 0 AND f.context_lead = 'Rent' THEN f.sk_house_listing_flow ELSE NULL END) AS leads_rent,
		COUNT(DISTINCT CASE WHEN sk_lead_date > 0 AND f.context_lead = 'Sale' THEN f.sk_house_listing_flow ELSE NULL END) AS leads_sale,
		COUNT(DISTINCT CASE WHEN sk_lead_date > 0 AND (f.context_lead = 'Hybrid' OR f.context_lead = NULL) THEN f.sk_house_listing_flow ELSE NULL END) AS leads_hybrid,
		COUNT(NULL) AS prospects_rent,
		COUNT(NULL) AS prospects_sale,
		COUNT(NULL) AS prospects_hybrid,
		COUNT(NULL) AS qualifieds_rent,
		COUNT(NULL) AS qualifieds_sale,
		COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
		COUNT(NULL) AS opportunities_rent,
		COUNT(NULL) AS opportunities_sale,
		COUNT(NULL) AS opportunities_hybrid,
		COUNT(NULL) AS first_listings_rent,
		COUNT(NULL) AS first_listings_sale,
		COUNT(NULL) AS first_listings_hybrid,
		SUM(CAST(0 AS FLOAT)) AS cost_sale,
		SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
		SUM(CAST(0 AS FLOAT)) AS budget_sale,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
		SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        dw_datamarts.lead_listing_flows AS f
    JOIN dw_public.dim_lead AS dl
        ON dl.sk_lead = f.sk_lead
    JOIN dw_public.dim_region AS dr
        ON f.sk_region = dr.sk_region
    LEFT JOIN datalake_wololo_clean.prospect p
        ON p.id_reference = f.sk_lead
    LEFT JOIN dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = f.sk_user_lead_affiliate
        AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(f.sk_lead_date AS STRING),'yyyyMMdd')))
    WHERE
        f.sk_lead_date > 0
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL

  -------------------------------------
  -- Supply Prospects Volume --
  -------------------------------------
    SELECT
		f.sk_prospect_date AS sk_date,
		COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        ac.affiliate_volumetry,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Partners'
            ELSE COALESCE(f.mkt_origin,'')
        END AS mkt_origin,
        COALESCE(f.mkt_channel,'') AS mkt_channel,
        COALESCE(f.mkt_medium,'') AS mkt_medium,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Spinver'
            ELSE COALESCE(f.mkt_source,'')
        END AS mkt_source,
		COALESCE(dl.utm_campaign,'') AS utm_campaign,
		COALESCE(dl.utm_content,'') AS utm_content,
		COALESCE(dl.utm_term,'') AS utm_term,
		COALESCE(p.origin_phone,'') AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
		COUNT(NULL) AS leads_rent,
		COUNT(NULL) AS leads_sale,
		COUNT(NULL) AS leads_hybrid,
		COUNT(DISTINCT CASE WHEN sk_prospect_date > 0 AND f.context_prospect= 'Rent' THEN f.sk_house_listing_flow ELSE NULL END) AS prospects_rent,
		COUNT(DISTINCT CASE WHEN sk_prospect_date > 0 AND f.context_prospect = 'Sale' THEN f.sk_house_listing_flow ELSE NULL END) AS prospects_sale,
		COUNT(DISTINCT CASE WHEN sk_prospect_date > 0 AND (f.context_prospect = 'Hybrid' OR f.context_prospect = NULL) THEN f.sk_house_listing_flow ELSE NULL END) AS prospects_hybrid,
		COUNT(NULL) AS qualifieds_rent,
		COUNT(NULL) AS qualifieds_sale,
		COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
		COUNT(NULL) AS opportunities_rent,
		COUNT(NULL) AS opportunities_sale,
		COUNT(NULL) AS opportunities_hybrid,
		COUNT(NULL) AS first_listings_rent,
		COUNT(NULL) AS first_listings_sale,
		COUNT(NULL) AS first_listings_hybrid,
		SUM(CAST(0 AS FLOAT)) AS cost_sale,
		SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
		SUM(CAST(0 AS FLOAT)) AS budget_sale,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
		SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        dw_datamarts.lead_listing_flows AS f
    JOIN dw_public.dim_lead AS dl
        ON dl.sk_lead = f.sk_lead
    JOIN dw_public.dim_region AS dr
        ON f.sk_region = dr.sk_region
    LEFT JOIN datalake_wololo_clean.prospect p
        ON p.id_reference = f.sk_lead
    LEFT JOIN dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = f.sk_user_lead_affiliate
        AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(f.sk_lead_date AS STRING),'yyyyMMdd')))
    WHERE
        f.sk_prospect_date > 0
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL
    --------------------------------------
    -- Supply Qualifieds Volume --
    --------------------------------------
    SELECT
		f.sk_qualified_date AS sk_date,
		COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        ac.affiliate_volumetry,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Partners'
            ELSE COALESCE(f.mkt_origin,'')
        END AS mkt_origin,
        COALESCE(f.mkt_channel,'') AS mkt_channel,
        COALESCE(f.mkt_medium,'') AS mkt_medium,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Spinver'
            ELSE COALESCE(f.mkt_source,'')
        END AS mkt_source,
		COALESCE(dl.utm_campaign,'') AS utm_campaign,
		COALESCE(dl.utm_content,'') AS utm_content,
		COALESCE(dl.utm_term,'') AS utm_term,
		COALESCE(p.origin_phone,'') AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
		COUNT(NULL) AS leads_rent,
		COUNT(NULL) AS leads_sale,
		COUNT(NULL) AS leads_hybrid,
		COUNT(NULL) AS prospects_rent,
		COUNT(NULL) AS prospects_sale,
		COUNT(NULL) AS prospects_hybrid,
		COUNT(DISTINCT CASE WHEN sk_qualified_date > 0 AND f.context_qualified = 'Rent' THEN f.sk_house_listing_flow ELSE NULL END) AS qualifieds_rent,
		COUNT(DISTINCT CASE WHEN sk_qualified_date > 0 AND f.context_qualified = 'Sale' THEN f.sk_house_listing_flow ELSE NULL END) AS qualifieds_sale,
		COUNT(DISTINCT CASE WHEN sk_qualified_date > 0 AND (f.context_qualified = 'Hybrid' OR f.context_qualified = NULL) THEN f.sk_house_listing_flow ELSE NULL END) AS qualifieds_hybrid,
		COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
		COUNT(NULL) AS opportunities_sale,
		COUNT(NULL) AS opportunities_hybrid,
		COUNT(NULL) AS first_listings_rent,
		COUNT(NULL) AS first_listings_sale,
		COUNT(NULL) AS first_listings_hybrid,
		SUM(CAST(0 AS FLOAT)) AS cost_sale,
		SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
		SUM(CAST(0 AS FLOAT)) AS budget_sale,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
		SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        dw_datamarts.lead_listing_flows AS f
    JOIN dw_public.dim_lead AS dl
        ON dl.sk_lead = f.sk_lead
    JOIN dw_public.dim_region AS dr
        ON f.sk_region = dr.sk_region
    LEFT JOIN datalake_wololo_clean.prospect p
        ON p.id_reference = f.sk_lead
    LEFT JOIN dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = f.sk_user_lead_affiliate
        AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(f.sk_lead_date AS STRING),'yyyyMMdd')))
    WHERE
        f.sk_qualified_date > 0
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL

    --------------------------------------
    -- Supply Available Qualifieds Volume --
    --------------------------------------
    SELECT
		f.sk_available_qualified_date AS sk_date,
		COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        ac.affiliate_volumetry,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Partners'
            ELSE COALESCE(f.mkt_origin,'')
        END AS mkt_origin,
        COALESCE(f.mkt_channel,'') AS mkt_channel,
        COALESCE(f.mkt_medium,'') AS mkt_medium,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Spinver'
            ELSE COALESCE(f.mkt_source,'')
        END AS mkt_source,
		COALESCE(dl.utm_campaign,'') AS utm_campaign,
		COALESCE(dl.utm_content,'') AS utm_content,
		COALESCE(dl.utm_term,'') AS utm_term,
		COALESCE(p.origin_phone,'') AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
		COUNT(NULL) AS leads_rent,
		COUNT(NULL) AS leads_sale,
		COUNT(NULL) AS leads_hybrid,
		COUNT(NULL) AS prospects_rent,
		COUNT(NULL) AS prospects_sale,
		COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
		COUNT(DISTINCT CASE WHEN sk_available_qualified_date > 0 AND f.context_available_qualified = 'Rent' THEN f.sk_house_listing_flow ELSE NULL END) AS available_qualifieds_rent,
		COUNT(DISTINCT CASE WHEN sk_available_qualified_date > 0 AND f.context_available_qualified = 'Sale' THEN f.sk_house_listing_flow ELSE NULL END) AS available_qualifieds_sale,
		COUNT(DISTINCT CASE WHEN sk_available_qualified_date > 0 AND (f.context_available_qualified = 'Hybrid' OR f.context_available_qualified = NULL) THEN f.sk_house_listing_flow ELSE NULL END) AS available_qualifieds_hybrid,
		COUNT(NULL) AS opportunities_rent,
		COUNT(NULL) AS opportunities_sale,
		COUNT(NULL) AS opportunities_hybrid,
		COUNT(NULL) AS first_listings_rent,
		COUNT(NULL) AS first_listings_sale,
		COUNT(NULL) AS first_listings_hybrid,
		SUM(CAST(0 AS FLOAT)) AS cost_sale,
		SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
		SUM(CAST(0 AS FLOAT)) AS budget_sale,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
		SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        dw_datamarts.lead_listing_flows AS f
    JOIN dw_public.dim_lead AS dl
        ON dl.sk_lead = f.sk_lead
    JOIN dw_public.dim_region AS dr
        ON f.sk_region = dr.sk_region
    LEFT JOIN datalake_wololo_clean.prospect p
        ON p.id_reference = f.sk_lead
    LEFT JOIN dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = f.sk_user_lead_affiliate
        AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(f.sk_lead_date AS STRING),'yyyyMMdd')))
    WHERE
        f.sk_available_qualified_date > 0
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL

  -----------------------------------------
  -- Supply Opportunities Volume --
  -----------------------------------------
    SELECT
		f.sk_opportunity_date AS sk_date,
		COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        ac.affiliate_volumetry,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Partners'
            ELSE COALESCE(f.mkt_origin,'')
        END AS mkt_origin,
        COALESCE(f.mkt_channel,'') AS mkt_channel,
        COALESCE(f.mkt_medium,'') AS mkt_medium,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Spinver'
            ELSE COALESCE(f.mkt_source,'')
        END AS mkt_source,
		COALESCE(dl.utm_campaign,'') AS utm_campaign,
		COALESCE(dl.utm_content,'') AS utm_content,
		COALESCE(dl.utm_term,'') AS utm_term,
		COALESCE(p.origin_phone,'') AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
		COUNT(NULL) AS leads_rent,
		COUNT(NULL) AS leads_sale,
		COUNT(NULL) AS leads_hybrid,
		COUNT(NULL) AS prospects_rent,
		COUNT(NULL) AS prospects_sale,
		COUNT(NULL) AS prospects_hybrid,
		COUNT(NULL) AS qualifieds_rent,
		COUNT(NULL) AS qualifieds_sale,
		COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
		COUNT(DISTINCT CASE WHEN sk_opportunity_date > 0 AND f.context_opportunity = 'Rent' THEN f.sk_house_listing_flow ELSE NULL END) AS opportunities_rent,
		COUNT(DISTINCT CASE WHEN sk_opportunity_date > 0 AND f.context_opportunity = 'Sale' THEN f.sk_house_listing_flow ELSE NULL END) AS opportunities_sale,
		COUNT(DISTINCT CASE WHEN sk_opportunity_date > 0 AND (f.context_opportunity = 'Hybrid' OR f.context_opportunity = NULL) THEN f.sk_house_listing_flow ELSE NULL END) AS opportunities_hybrid,
		COUNT(NULL) AS first_listings_rent,
		COUNT(NULL) AS first_listings_sale,
		COUNT(NULL) AS first_listings_hybrid,
		SUM(CAST(0 AS FLOAT)) AS cost_sale,
		SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
		SUM(CAST(0 AS FLOAT)) AS budget_sale,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
		SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        dw_datamarts.lead_listing_flows AS f
    JOIN dw_public.dim_lead AS dl
        ON dl.sk_lead = f.sk_lead
    JOIN dw_public.dim_region AS dr
        ON f.sk_region = dr.sk_region
    LEFT JOIN datalake_wololo_clean.prospect p
        ON p.id_reference = f.sk_lead
    LEFT JOIN dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = f.sk_user_lead_affiliate
        AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(f.sk_lead_date AS STRING),'yyyyMMdd')))
    WHERE
        f.sk_opportunity_date > 0
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL

  ------------------------------------------
  -- Supply First Listings Volume --
  ------------------------------------------
    SELECT
		f.sk_first_listing_date AS sk_date,
		COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        ac.affiliate_volumetry,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Partners'
            ELSE COALESCE(f.mkt_origin,'')
        END AS mkt_origin,
        COALESCE(f.mkt_channel,'') AS mkt_channel,
        COALESCE(f.mkt_medium,'') AS mkt_medium,
        CASE
            WHEN f.sk_user_lead_affiliate IN (360754,912255,1711931,2257503) THEN 'Spinver'
            ELSE COALESCE(f.mkt_source,'')
        END AS mkt_source,
		COALESCE(dl.utm_campaign,'') AS utm_campaign,
		COALESCE(dl.utm_content,'') AS utm_content,
		COALESCE(dl.utm_term,'') AS utm_term,
		COALESCE(p.origin_phone,'') AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
		COUNT(NULL) AS leads_rent,
		COUNT(NULL) AS leads_sale,
		COUNT(NULL) AS leads_hybrid,
		COUNT(NULL) AS prospects_rent,
		COUNT(NULL) AS prospects_sale,
		COUNT(NULL) AS prospects_hybrid,
		COUNT(NULL) AS qualifieds_rent,
		COUNT(NULL) AS qualifieds_sale,
		COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
		COUNT(NULL) AS opportunities_rent,
		COUNT(NULL) AS opportunities_sale,
		COUNT(NULL) AS opportunities_hybrid,
		COUNT(DISTINCT CASE WHEN f.sk_first_listing_date > 0 AND f.context_first_listing = 'Rent' THEN f.sk_house_listing_flow ELSE NULL END) AS first_listings_rent,
		COUNT(DISTINCT CASE WHEN f.sk_first_listing_date > 0 AND f.context_first_listing = 'Sale' THEN f.sk_house_listing_flow ELSE NULL END) AS first_listings_sale,
		COUNT(DISTINCT CASE WHEN f.sk_first_listing_date > 0 AND (f.context_first_listing = 'Hybrid' OR f.context_first_listing = NULL) THEN f.sk_house_listing_flow ELSE NULL END) AS first_listings_hybrid,
		SUM(CAST(0 AS FLOAT)) AS cost_sale,
		SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
		SUM(CAST(0 AS FLOAT)) AS budget_sale,
		SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
		SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
		SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
		SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
		SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        dw_datamarts.lead_listing_flows AS f
    JOIN dw_public.dim_lead AS dl
        ON dl.sk_lead = f.sk_lead
    JOIN dw_public.dim_region AS dr
        ON f.sk_region = dr.sk_region
    JOIN dw_public.dim_date AS dd
        ON f.sk_first_listing_date = dd.sk_date
    LEFT JOIN datalake_wololo_clean.prospect p
        ON p.id_reference = f.sk_lead
    LEFT JOIN dw_datamarts.affiliates_clusters ac
        ON ac.sk_user = f.sk_user_lead_affiliate
        AND ac.month_start = DATE_TRUNC('MONTH',(TO_DATE(CAST(f.sk_lead_date AS STRING),'yyyyMMdd')))
    WHERE
        f.sk_first_listing_date > 0
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL

  -----------------------------------------
  -- Supply Marketing Investment --
  -----------------------------------------
    (
    WITH
    affiliates AS (
        WITH
        ia_fact_cost AS (
            SELECT
                fc.id_date as sk_date,
                mkt_origin,
                mkt_channel,
                mkt_medium,
                mkt_source,
                utm_campaign,
                utm_content,
                utm_term,
                fc.city_group,
                CASE
                    WHEN fc.mkt_source IN ('Twilio', 'Movile') THEN 'Notification'
                    ELSE mkt_source
                END AS source,
                NULL AS business_context,
                fc.cost
            FROM
                datalake_marketing_costs.daily_costs fc
            WHERE fc.mkt_origin = 'Indica Aí - General'
            AND fc.mkt_source <> 'Spinver'
        ),
        ia_affiliate_commission_costs AS (
            WITH commission_costs AS (
                SELECT
                    DISTINCT f.sk_rh_accounting_entry,
                    d.mkt_origin,
                    d.city_group,
                    f.sk_date,
                    d.commission_type AS source,
                    d.cost_center_code,
                    f.cost
                FROM
                    dw_quintoandar.fact_affiliate_costs f
                LEFT JOIN
                    dw_quintoandar.dim_affiliate_cost d
                    ON f.sk_rh_accounting_entry = d.sk_rh_accounting_entry
                WHERE sk_user NOT IN (360754,912255,1711931,2257503)
                )
                SELECT
                    cc.sk_date,
                    cc.mkt_origin,
                    CAST(NULL AS STRING) AS mkt_channel,
                    CAST(NULL AS STRING) AS mkt_medium,
                    CAST(NULL AS STRING) AS mkt_source,
                    CAST(NULL AS STRING) AS utm_campaign,
                    CAST(NULL AS STRING) AS utm_content,
                    CAST(NULL AS STRING) AS utm_term,
                    cc.city_group,
                    cc.source,
                    CASE
                        WHEN cc.cost_center_code = 'C046' THEN 'Sale'
                        ELSE 'Rent'
                    END AS business_context,
                    SUM(cc.cost) AS cost
                FROM
                    commission_costs cc
                WHERE
                    cc.sk_date >= 20210125
                GROUP BY
                    1,2,3,4,5,6,7,8,9,10,11
        ),
        promo_bonus AS (
            WITH segmentation_promo_bonus AS(
            SELECT
                sk_date,
                CASE
                    WHEN affiliate_type = 'Standard' THEN 'Indica Aí - General'
                    WHEN affiliate_type = 'Agent' THEN 'Indica Aí - Agents'
                    WHEN affiliate_type = 'Doorman' THEN 'Doorman'
                    ELSE affiliate_type
                END AS mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term,
                city_group,
                'Promo Bonus' AS source,
                'Rent' AS business_context,
                SUM(final_bonus_rent) AS cost
            FROM
                dw_datamarts.performance_marketing_promotional_bonus_costs_daily
            WHERE final_bonus_rent > 0
            AND sk_date >= 20210208
            AND sk_date < 20210701
            GROUP BY 1,2,3,4,5,6,7,8,9,10,11

            UNION ALL

            SELECT
                sk_date,
                CASE
                    WHEN affiliate_type = 'Standard' THEN 'Indica Aí - General'
                    WHEN affiliate_type = 'Agent' THEN 'Indica Aí - Agents'
                    WHEN affiliate_type = 'Doorman' THEN 'Doorman'
                    ELSE affiliate_type
                END AS mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term,
                city_group,
                'Promo Bonus' AS source,
                'Sale' AS business_context,
                SUM(final_bonus_sale) AS cost
            FROM
                dw_datamarts.performance_marketing_promotional_bonus_costs_daily
            WHERE final_bonus_sale > 0
            AND sk_date >= 20210208
            AND sk_date < 20210701
            GROUP BY 1,2,3,4,5,6,7,8,9,10,11
        ),
        cluster_promo_bonus AS(
            SELECT
                sk_date,
                CASE
                    WHEN affiliate_type = 'Standard' THEN 'Indica Aí - General'
                    WHEN affiliate_type = 'Agent' THEN 'Indica Aí - Agents'
                    WHEN affiliate_type = 'Doorman' THEN 'Doorman'
                    ELSE affiliate_type
                END AS mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term,
                city_group,
                'Promo Bonus' AS source,
                'Rent' AS business_context,
                SUM(final_bonus_rent) AS cost
            FROM
                dw_datamarts.performance_marketing_cluster_promotional_bonus_costs
            WHERE final_bonus_rent > 0
            AND sk_date >= 20210701
            GROUP BY 1,2,3,4,5,6,7,8,9,10,11

            UNION ALL

            SELECT
                sk_date,
                CASE
                    WHEN affiliate_type = 'Standard' THEN 'Indica Aí - General'
                    WHEN affiliate_type = 'Agent' THEN 'Indica Aí - Agents'
                    WHEN affiliate_type = 'Doorman' THEN 'Doorman'
                    ELSE affiliate_type
                END AS mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term,
                city_group,
                'Promo Bonus' AS source,
                'Sale' AS business_context,
                SUM(final_bonus_sale) AS cost
            FROM
                dw_datamarts.performance_marketing_cluster_promotional_bonus_costs
            WHERE final_bonus_sale > 0
            AND sk_date >= 20210701
            GROUP BY 1,2,3,4,5,6,7,8,9,10,11
        )
    SELECT * FROM segmentation_promo_bonus
    UNION ALL
    SELECT * FROM cluster_promo_bonus
        ),
        ia_fact_affiliate_transposed AS (
            SELECT
                id_date AS sk_date,
                mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term,
                city_group,
                'Commission Listing' AS source,
                NULL AS business_context,
                commission_listing_cost AS cost
            FROM
                datalake_affiliates_cost_attributions.affiliates_cost_attributions
            WHERE
                id_date < 20210125

            UNION ALL

            SELECT
                id_date AS sk_date,
                mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term,
                city_group,
                'Commission Rent' AS source,
                NULL AS business_context,
                commission_rent_cost AS cost
            FROM
                datalake_affiliates_cost_attributions.affiliates_cost_attributions
            WHERE
                id_date < 20210125

            UNION ALL

            SELECT
                id_date AS sk_date,
                mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term, city_group,
                'Commission MGM' AS source,
                NULL AS business_context,
                commission_mgm_cost AS cost
            FROM
                datalake_affiliates_cost_attributions.affiliates_cost_attributions
            WHERE
                id_date < 20210125

            UNION ALL

            SELECT
                id_date AS sk_date,
                mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term,
                city_group,
                'Commission Tradecom' AS source,
                NULL AS business_context,
                commission_tradecom_cost AS cost
            FROM
                datalake_affiliates_cost_attributions.affiliates_cost_attributions

            UNION ALL

            SELECT
                id_date AS sk_date,
                mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term,
                city_group,
                'Promo Bonus' AS source,
                NULL AS business_context,
                promotional_bonus_cost AS cost
            FROM
                datalake_affiliates_cost_attributions.affiliates_cost_attributions
            WHERE
                id_date < 20210208

            UNION ALL

            SELECT
                id_date AS sk_date,
                mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term,
                city_group,
                'Notification' AS source,
                NULL AS business_context,
                notification_cost AS cost
            FROM
                datalake_affiliates_cost_attributions.affiliates_cost_attributions

            UNION ALL

            SELECT
                id_date AS sk_date,
                mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term,
                city_group, 'Other' AS source,
                NULL AS business_context,
                other_cost AS cost
            FROM
                datalake_affiliates_cost_attributions.affiliates_cost_attributions
        ),
        ia_provisioned_costs AS (
            SELECT
                CAST(DATE_FORMAT(dt_created, 'yyyyMMdd') as BIGINT) AS sk_date,
                mkt_origin,
                CAST(NULL AS STRING) AS mkt_channel,
                CAST(NULL AS STRING) AS mkt_medium,
                CAST(NULL AS STRING) AS mkt_source,
                CAST(NULL AS STRING) AS utm_campaign,
                CAST(NULL AS STRING) AS utm_content,
                CAST(NULL AS STRING) AS utm_term,
                city_group,
                source,
                NULL AS business_context,
                cost
            FROM
                datalake_gsheets_clean.provisioned_costs_import
        ),
        ia_total_cost AS (
            SELECT  * FROM ia_fact_cost
            UNION ALL
            SELECT * FROM ia_fact_affiliate_transposed
            UNION ALL
            SELECT * FROM ia_provisioned_costs
            UNION ALL
            SELECT * FROM ia_affiliate_commission_costs
            UNION ALL
            SELECT * FROM promo_bonus
        ),
        base AS (
            SELECT
                iac.sk_date,
                iac.mkt_origin,
                iac.mkt_channel,
                iac.mkt_medium,
                iac.mkt_source,
                iac.utm_campaign,
                iac.utm_content,
                iac.utm_term,
                iac.city_group,
                iac.source,
                iac.business_context,
                SUM(iac.cost) AS costs
            FROM
                ia_total_cost iac
            JOIN dw_public.dim_date dd
                ON dd.sk_date = iac.sk_date
            WHERE
                iac.cost IS NOT NULL
                AND dd.date < CURRENT_DATE
            GROUP BY
                1,2,3,4,5,6,7,8,9,10,11
            HAVING
                costs>0
        )
        SELECT
            sk_date,
            city_group,
            business_context,
            mkt_origin,
            mkt_channel,
            mkt_medium,
            mkt_source,
            utm_campaign,
            utm_content,
            utm_term,
            SUM(costs) AS costs
        FROM
            base
        GROUP BY
            1,2,3,4,5,6,7,8,9,10
        ),
        affiliates_sale_cost AS (
            SELECT
                sk_date,
                city_group,
                CAST(NULL AS STRING) AS affiliate_volumetry,
                replace(mkt_origin,' Sale','') AS mkt_origin,
                mkt_channel,
                mkt_medium,
                mkt_source,
                utm_campaign,
                utm_content,
                utm_term,
                CAST(NULL AS STRING) AS origin_phone,
                SUM(CAST(0 AS FLOAT)) AS tof_rent,
                SUM(CAST(0 AS FLOAT)) AS tof_sale,
                COUNT(NULL) AS leads_rent,
                COUNT(NULL) AS leads_sale,
                COUNT(NULL) AS leads_hybrid,
                COUNT(NULL) AS prospects_rent,
                COUNT(NULL) AS prospects_sale,
                COUNT(NULL) AS prospects_hybrid,
                COUNT(NULL) AS qualifieds_rent,
                COUNT(NULL) AS qualifieds_sale,
                COUNT(NULL) AS qualifieds_hybrid,
                COUNT(NULL) AS available_qualifieds_rent,
                COUNT(NULL) AS available_qualifieds_sale,
                COUNT(NULL) AS available_qualifieds_hybrid,
                COUNT(NULL) AS opportunities_rent,
                COUNT(NULL) AS opportunities_sale,
                COUNT(NULL) AS opportunities_hybrid,
                COUNT(NULL) AS first_listings_rent,
                COUNT(NULL) AS first_listings_sale,
                COUNT(NULL) AS first_listings_hybrid,
                CAST(SUM(costs) AS FLOAT) AS cost_sale,
                SUM(CAST(0 AS FLOAT)) AS cost_rental,
                SUM(CAST(0 AS FLOAT)) AS tof_target,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
                SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
                SUM(CAST(0 AS FLOAT)) AS budget_sale,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
                SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
                SUM(CAST(0 AS FLOAT)) AS budget_rental,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
            FROM
                affiliates
            WHERE
                business_context = 'Sale'
                OR (business_context is NULL AND mkt_origin IN ('Doorman Sale','Indica Aí - Agents Sale','Indica Aí - General Sale'))
            GROUP BY
                1,2,3,4,5,6,7,8,9,10,11
        ),
        supply_affiliates_cost AS (
            SELECT
                sk_date,
                city_group,
                CAST(NULL AS STRING) AS affiliate_volumetry,
                mkt_origin,
                mkt_channel,
                mkt_medium,
                mkt_source,
                utm_campaign,
                utm_content,
                utm_term,
                CAST(NULL AS STRING) AS origin_phone,
                SUM(CAST(0 AS FLOAT)) AS tof_rent,
                SUM(CAST(0 AS FLOAT)) AS tof_sale,
                COUNT(NULL) AS leads_rent,
                COUNT(NULL) AS leads_sale,
                COUNT(NULL) AS leads_hybrid,
                COUNT(NULL) AS prospects_rent,
                COUNT(NULL) AS prospects_sale,
                COUNT(NULL) AS prospects_hybrid,
                COUNT(NULL) AS qualifieds_rent,
                COUNT(NULL) AS qualifieds_sale,
                COUNT(NULL) AS qualifieds_hybrid,
                COUNT(NULL) AS available_qualifieds_rent,
                COUNT(NULL) AS available_qualifieds_sale,
                COUNT(NULL) AS available_qualifieds_hybrid,
                COUNT(NULL) AS opportunities_rent,
                COUNT(NULL) AS opportunities_sale,
                COUNT(NULL) AS opportunities_hybrid,
                COUNT(NULL) AS first_listings_rent,
                COUNT(NULL) AS first_listings_sale,
                COUNT(NULL) AS first_listings_hybrid,
                SUM(CAST(0 AS FLOAT)) AS cost_sale,
                CAST(SUM(costs) AS FLOAT) AS cost_rental,
                SUM(CAST(0 AS FLOAT)) AS tof_target,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
                SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
                SUM(CAST(0 AS FLOAT)) AS budget_sale,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
                SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
                SUM(CAST(0 AS FLOAT)) AS budget_rental,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
            FROM
                affiliates
            WHERE
                business_context = 'Rent'
                OR (business_context is NULL AND mkt_origin IN ('Doorman','Indica Aí - Agents','Indica Aí - General'))
            GROUP BY
                1,2,3,4,5,6,7,8,9,10,11
        ),
        supply_landlords_cost AS (
            SELECT
                dbt.sk_date AS sk_date,
                co.city_group,
                CAST(NULL AS STRING) AS affiliate_volumetry,
                CASE WHEN co.mkt_origin = 'Owner PWA' THEN 'PWA - '||co.mkt_channel ELSE co.mkt_origin END AS mkt_origin,
                co.mkt_channel AS mkt_channel,
                co.mkt_medium AS mkt_medium,
                co.mkt_source AS mkt_source,
                co.utm_campaign AS utm_campaign,
                co.utm_content AS utm_content,
                co.utm_term AS utm_term,
                CAST(NULL AS STRING) AS origin_phone,
                SUM(CAST(0 AS FLOAT)) AS tof_rent,
                SUM(CAST(0 AS FLOAT)) AS tof_sale,
                COUNT(NULL) AS leads_rent,
                COUNT(NULL) AS leads_sale,
                COUNT(NULL) AS leads_hybrid,
                COUNT(NULL) AS prospects_rent,
                COUNT(NULL) AS prospects_sale,
                COUNT(NULL) AS prospects_hybrid,
                COUNT(NULL) AS qualifieds_rent,
                COUNT(NULL) AS qualifieds_sale,
                COUNT(NULL) AS qualifieds_hybrid,
                COUNT(NULL) AS available_qualifieds_rent,
                COUNT(NULL) AS available_qualifieds_sale,
                COUNT(NULL) AS available_qualifieds_hybrid,
                COUNT(NULL) AS opportunities_rent,
                COUNT(NULL) AS opportunities_sale,
                COUNT(NULL) AS opportunities_hybrid,
                COUNT(NULL) AS first_listings_rent,
                COUNT(NULL) AS first_listings_sale,
                COUNT(NULL) AS first_listings_hybrid,
                SUM(CAST(0 AS FLOAT)) AS cost_sale,
                CAST(SUM(co.cost) AS FLOAT) AS cost_rental,
                SUM(CAST(0 AS FLOAT)) AS tof_target,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
                SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
                SUM(CAST(0 AS FLOAT)) AS budget_sale,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
                SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
                SUM(CAST(0 AS FLOAT)) AS budget_rental,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
            FROM
                datalake_marketing_costs.daily_costs co
            JOIN
                dw_public.dim_date dbt
                on dbt.sk_date = co.id_date
            WHERE
                co.funnel_side = 'supply'
                AND dbt.date BETWEEN '2020-01-01' AND (CURRENT_DATE - interval '1 day')
                AND co.mkt_origin IN ('Owner PWA','Price Calculator','New Channels','Test')
                AND co.mkt_channel != 'Girafa'
            GROUP BY
                1,2,3,4,5,6,7,8,9,10,11
        ),
        supply_sale_cost AS (
            SELECT
                dbt.sk_date AS sk_date,
                co.city_group AS city_group,
                CAST(NULL AS STRING) AS affiliate_volumetry,
                co.mkt_origin AS mkt_origin,
                co.mkt_channel AS mkt_channel,
                co.mkt_medium AS mkt_medium,
                co.mkt_source AS mkt_source,
                co.utm_campaign AS utm_campaign,
                co.utm_content AS utm_content,
                co.utm_term AS utm_term,
                CAST(NULL AS STRING) AS origin_phone,
                SUM(CAST(0 AS FLOAT)) AS tof_rent,
                SUM(CAST(0 AS FLOAT)) AS tof_sale,
                COUNT(NULL) AS leads_rent,
                COUNT(NULL) AS leads_sale,
                COUNT(NULL) AS leads_hybrid,
                COUNT(NULL) AS prospects_rent,
                COUNT(NULL) AS prospects_sale,
                COUNT(NULL) AS prospects_hybrid,
                COUNT(NULL) AS qualifieds_rent,
                COUNT(NULL) AS qualifieds_sale,
                COUNT(NULL) AS qualifieds_hybrid,
                COUNT(NULL) AS available_qualifieds_rent,
                COUNT(NULL) AS available_qualifieds_sale,
                COUNT(NULL) AS available_qualifieds_hybrid,
                COUNT(NULL) AS opportunities_rent,
                COUNT(NULL) AS opportunities_sale,
                COUNT(NULL) AS opportunities_hybrid,
                COUNT(NULL) AS first_listings_rent,
                COUNT(NULL) AS first_listings_sale,
                COUNT(NULL) AS first_listings_hybrid,
                CAST(SUM(co.cost) AS FLOAT) AS cost_sale,
                SUM(CAST(0 AS FLOAT)) AS cost_rental,
                SUM(CAST(0 AS FLOAT)) AS tof_target,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
                SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
                SUM(CAST(0 AS FLOAT)) AS budget_sale,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
                SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
                SUM(CAST(0 AS FLOAT)) AS budget_rental,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
            FROM
                datalake_marketing_costs.daily_costs co
            JOIN
                dw_public.dim_date dbt
                ON dbt.sk_date = co.id_date
            WHERE
                co.account_name IN ('quintoandar_supply_sale_display', 'quintoandar_supply_sale', 'supply_landlords_sale', 'supply_landlords', 'imovelweb_supply')
                AND co.mkt_origin IN ('Owner PWA - Sale', 'Price Calculator - Sale')
            GROUP BY
                1,2,3,4,5,6,7,8,9,10,11
        ),
        supply_ciq_cost AS (
            SELECT
                dbt.sk_date AS sk_date,
                co.city_group AS city_group,
                CAST(NULL AS STRING) AS affiliate_volumetry,
                co.mkt_origin AS mkt_origin,
                co.mkt_channel AS mkt_channel,
                co.mkt_medium AS mkt_medium,
                co.mkt_source AS mkt_source,
                co.utm_campaign AS utm_campaign,
                co.utm_content AS utm_content,
                co.utm_term AS utm_term,
                CAST(NULL AS STRING) AS origin_phone,
                SUM(CAST(0 AS FLOAT)) AS tof_rent,
                SUM(CAST(0 AS FLOAT)) AS tof_sale,
                COUNT(NULL) AS leads_rent,
                COUNT(NULL) AS leads_sale,
                COUNT(NULL) AS leads_hybrid,
                COUNT(NULL) AS prospects_rent,
                COUNT(NULL) AS prospects_sale,
                COUNT(NULL) AS prospects_hybrid,
                COUNT(NULL) AS qualifieds_rent,
                COUNT(NULL) AS qualifieds_sale,
                COUNT(NULL) AS qualifieds_hybrid,
                COUNT(NULL) AS available_qualifieds_rent,
                COUNT(NULL) AS available_qualifieds_sale,
                COUNT(NULL) AS available_qualifieds_hybrid,
                COUNT(NULL) AS opportunities_rent,
                COUNT(NULL) AS opportunities_sale,
                COUNT(NULL) AS opportunities_hybrid,
                COUNT(NULL) AS first_listings_rent,
                COUNT(NULL) AS first_listings_sale,
                COUNT(NULL) AS first_listings_hybrid,
                SUM(CAST(0 AS FLOAT)) AS cost_sale,
                CAST(SUM(co.cost) AS FLOAT) AS cost_rental,
                SUM(CAST(0 AS FLOAT)) AS tof_target,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
                SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
                SUM(CAST(0 AS FLOAT)) AS budget_sale,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
                SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
                SUM(CAST(0 AS FLOAT)) AS budget_rental,
                SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
                SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
                SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
                SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
            FROM
                datalake_marketing_costs.daily_costs co
            JOIN
                dw_public.dim_date dbt
                ON dbt.sk_date = co.id_date
            WHERE
                co.mkt_origin = 'CIQ'
            GROUP BY
                1,2,3,4,5,6,7,8,9,10,11
        ),
        cost_union AS (
            SELECT * FROM supply_affiliates_cost
            UNION ALL
            SELECT * FROM supply_landlords_cost
            UNION ALL
            SELECT * FROM supply_sale_cost
            UNION ALL
            SELECT * FROM affiliates_sale_cost
            UNION ALL
            SELECT * FROM supply_ciq_cost
        )

        SELECT
            *
        FROM
            cost_union
        WHERE
            sk_date < CAST(DATE_FORMAT(CURRENT_DATE, 'yyyyMMdd') as BIGINT)
            AND (cost_sale > 0 OR cost_rental > 0)
            AND (cost_sale IS NOT NULL OR cost_rental IS NOT NULL)
        )

    UNION ALL

    ------------------------------------------
    -- Supply ForSale Funnel Targets  - NEW --
    ------------------------------------------
    SELECT
        str.id_date AS sk_date,
        CAST(COALESCE(NULLIF(str.city_group, ''),'Not Mapped') AS STRING) AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        str.supply_origin AS mkt_origin,
        str.supply_channel AS mkt_channel,
        str.supply_medium AS mkt_medium,
        str.supply_source AS mkt_source,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
        SUM(str.prospects) AS prospects_target_sale,
        SUM(str.qualifieds) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(str.opportunities) AS opportunities_target_sale,
        SUM(str.first_listings) AS first_listings_target_sale,
        SUM(str.cost_per_source) AS budget_sale,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
        SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        datalake_gsheets_clean.daily_target_supply_sale str
    WHERE
        str.dt_target >= DATE('2021-04-01')
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL

    -------------------------------------------
    -- Supply ForRental Funnel Targets - NEW --
    -------------------------------------------
    SELECT
        str.id_date AS sk_date,
        CAST(COALESCE(NULLIF(str.city_group, ''),'Not Mapped') AS STRING) AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        str.supply_origin AS mkt_origin,
        str.supply_channel AS mkt_channel,
        str.supply_medium AS mkt_medium,
        str.supply_source AS mkt_source,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
        SUM(CAST(0 AS FLOAT)) AS budget_sale,
        SUM(str.prospects) AS prospects_target_rental,
        SUM(str.qualifieds) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
        SUM(str.opportunities) AS opportunities_target_rental,
        SUM(str.first_listings) AS first_listings_target_rental,
        SUM(str.cost_per_source) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        datalake_gsheets_clean.daily_target_supply_rental str
    WHERE
        str.dt_target >= DATE('2021-04-01')
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL

    ---------------------------------------------------------
    -- Supply ForSale Prospects & Qualifieds Targets - OLD --
    ---------------------------------------------------------
(WITH targets AS
    (SELECT
        CAST(DATE_FORMAT(str.date, 'yyyyMMdd') as BIGINT) AS sk_date,
        CAST(COALESCE(NULLIF(str.city_group, ''),'Not Mapped') AS STRING) AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        CASE
            WHEN str.mkt_channel = 'Spinver' THEN 'Partners'
            WHEN str.mkt_origin = 'All' AND str.mkt_channel IN ('Organic', 'Paid', 'CRM/Notification') THEN 'Owner PWA'
            WHEN str.mkt_origin = 'All' AND str.mkt_channel NOT IN ('Organic', 'Paid', 'CRM/Notification')  THEN str.mkt_channel
            ELSE str.mkt_origin
        END AS mkt_origin,
        CAST(NULL AS STRING) AS  mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
        SUM(CAST(REPLACE(str.prospects,',','') AS FLOAT)) AS prospects_target_sale,
        SUM(CAST(REPLACE(str.qualifieds,',','') AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
        SUM(CAST(0 AS FLOAT)) AS budget_sale,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
        SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        datalake_gsheets_clean.sale_supply_targets str
    WHERE str.mkt_channel NOT IN ('All', 'Branded')
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11
    )
    SELECT
        *
    FROM targets
    WHERE sk_date < 20210401
    OR (sk_date >= 20210401
        AND mkt_origin NOT IN ('Price Calculator', 'New Channels')
        AND NOT(mkt_origin='Owner PWA' AND mkt_channel='Paid'))
)

    UNION ALL

    ----------------------------------------------------------------
    -- Supply ForSale Opportunities & First Listing Targets - OLD --
    ----------------------------------------------------------------
    SELECT
        CAST(DATE_FORMAT(str.date, 'yyyyMMdd') as BIGINT) AS sk_date,
        CAST(COALESCE(NULLIF(str.city_group, ''),'Not Mapped') AS STRING) AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        CASE
            WHEN str.mkt_channel = 'Spinver' THEN 'Partners'
            WHEN str.mkt_origin = 'All' AND str.mkt_channel IN ('Organic', 'Paid', 'CRM/Notification') THEN 'Owner PWA'
            WHEN str.mkt_origin = 'All' AND str.mkt_channel NOT IN ('Organic', 'Paid', 'CRM/Notification')  THEN str.mkt_channel
            ELSE str.mkt_origin
        END AS mkt_origin,
        CAST(NULL AS STRING) AS  mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(CAST(REPLACE(str.opportunities,',','') AS FLOAT)) AS opportunities_target_sale,
        SUM(CAST(REPLACE(str.first_listings,',','') AS FLOAT))AS first_listings_target_sale,
        SUM(CAST(0 AS FLOAT)) AS budget_sale,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
        SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        datalake_gsheets_clean.sale_supply_targets str
    WHERE str.mkt_channel NOT IN ('All', 'Branded')
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL
  -------------------------------------------
  -- Supply ForRental Prospects & Qualifieds Targets - OLD --
  -------------------------------------------
    SELECT
        CAST(DATE_FORMAT(str.date, 'yyyyMMdd') as BIGINT) AS sk_date,
        CAST(COALESCE(NULLIF(str.city_group,''),'Not Mapped') AS STRING) AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        CAST(NULLIF(str.supply_origin,'') AS STRING) AS mkt_origin,
        CAST(NULLIF(str.supply_channel,'') AS STRING) AS mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
        SUM(CAST(0 AS FLOAT)) AS budget_sale,
        SUM(CAST(REPLACE(str.prospect,',','') AS FLOAT)) AS prospects_target_rental,
        SUM(CAST(REPLACE(str.qualified,',','') AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
        SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        dw_datamarts.daily_target_volumes_supply str
    WHERE
        str.date < '2021-04-01'
        OR (str.date > '2021-04-01'
        AND str.supply_origin NOT IN ('Price Calculator', 'Price Calculator - Sale', 'New Channels')
        AND NOT(str.supply_origin='Owner PWA' AND str.supply_channel='Paid'))
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL

  ------------------------------------------------------------------
  -- Supply ForRental Opportunities & First Listing Targets - OLD --
  ------------------------------------------------------------------
    SELECT
        CAST(DATE_FORMAT(str.date, 'yyyyMMdd') as BIGINT) AS sk_date,
        CAST(COALESCE(NULLIF(str.city_group,''),'Not Mapped') AS STRING) AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        CAST(NULLIF(str.supply_origin,'') AS STRING) AS mkt_origin,
        CAST(NULLIF(str.supply_channel,'') AS STRING) AS mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
        SUM(CAST(0 AS FLOAT)) AS budget_sale,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
        SUM(CAST(REPLACE(str.opportunity,',','') AS FLOAT)) AS opportunities_target_rental,
        SUM(CAST(REPLACE(str.first_listing,',','') AS FLOAT)) AS first_listings_target_rental,
        SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        dw_datamarts.daily_target_volumes_supply str
   GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL

  ---------------------------------------
  -- Supply ForSale Cost Targets - OLD --
  ---------------------------------------
    SELECT
        CAST(DATE_FORMAT(sct.dt_created, 'yyyyMMdd') as BIGINT) AS sk_date,
        CAST(COALESCE(NULLIF(sct.city_group,''),'Not Mapped') AS STRING) AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        CASE
            WHEN sct.planning_mkt_level3 = 'PWA - Paid'
                THEN 'Owner PWA'
            WHEN sct.planning_mkt_level3 = 'Spinver'
                THEN 'Partners'
            ELSE sct.planning_mkt_level3
        END AS mkt_origin,
        CASE
            WHEN planning_mkt_level3  = 'PWA - Paid' THEN 'Paid'
            WHEN planning_mkt_level3 = 'Not Mapped' THEN 'Other'
            WHEN planning_mkt_level3 IN ('Autonomous Agent', 'Autonomuos Agent') THEN 'CIQ'
        ELSE planning_mkt_level3 END AS mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
        SUM(CAST(REPLACE(sct.monthly_budget,',','') AS FLOAT)) AS budget_sale,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
        SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        datalake_gsheets_clean.costs_targets sct
    WHERE
        planning_mkt_level1 = 'Supply'
        AND sct.dt_created < '2021-04-01'
        AND business = 'Sale'
        OR (planning_mkt_level1 = 'Supply'
            AND sct.dt_created >= '2021-04-01'
            AND business = 'Sale'
            AND planning_mkt_level3 NOT IN ('PWA - Paid', 'Price Calculator', 'New Channels'))
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11

    UNION ALL

  -----------------------------------------
  -- Supply ForRental Cost Targets - OLD --
  -----------------------------------------
    SELECT
        CAST(DATE_FORMAT(sct.dt_created, 'yyyyMMdd') as BIGINT) AS sk_date,
        CAST(COALESCE(nullif(sct.city_group,''),'Not Mapped') AS STRING) AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        CASE
            WHEN sct.planning_mkt_level3 = 'PWA - Paid'
                THEN 'Owner PWA'
            WHEN sct.planning_mkt_level3 = 'Spinver'
                THEN 'Partners'
            ELSE sct.planning_mkt_level3
        END AS mkt_origin,
        CASE
            WHEN planning_mkt_level3  = 'PWA - Paid' THEN 'Paid'
            WHEN planning_mkt_level3 = 'Not Mapped' THEN 'Other'
            WHEN planning_mkt_level3 IN ('Autonomous Agent', 'Autonomuos Agent') THEN 'CIQ'
        ELSE planning_mkt_level3 END AS mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
        SUM(CAST(0 AS FLOAT)) AS budget_sale,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
        SUM(CAST(REPLACE(sct.monthly_budget,',','') AS FLOAT)) AS budget_rental,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_unique,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_unique,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_unique,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_unique
    FROM
        datalake_gsheets_clean.costs_targets sct
    WHERE
        planning_mkt_level1 = 'Supply'
        AND sct.dt_created < '2021-04-01'
        AND business = 'Rental'
        OR (planning_mkt_level1 = 'Supply'
            AND sct.dt_created >= '2021-04-01'
            AND business = 'Rental'
            AND planning_mkt_level3 NOT IN ('PWA - Paid', 'Price Calculator', 'New Channels'))
    GROUP BY
        1,2,3,4,5,6,7,8,9,10,11
    
    UNION ALL

  -----------------------------------------
  -- Supply Unique Targets
  -----------------------------------------
    SELECT 
        CAST(DATE_FORMAT(uvt.date, 'yyyyMMdd') as BIGINT) AS sk_date,
        CAST(COALESCE(nullif(uvt.city_group,''),'Not Mapped') AS STRING) AS city_group,
        CAST(NULL AS STRING) AS affiliate_volumetry,
        COALESCE(uvt.supply_origin,'') AS mkt_origin,
        COALESCE(uvt.supply_channel,'') AS mkt_channel,
        COALESCE(uvt.supply_medium,'') AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_content,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS origin_phone,
        SUM(CAST(0 AS FLOAT)) AS tof_rent,
        SUM(CAST(0 AS FLOAT)) AS tof_sale,
        COUNT(NULL) AS leads_rent,
        COUNT(NULL) AS leads_sale,
        COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
        COUNT(NULL) AS prospects_sale,
        COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
        COUNT(NULL) AS qualifieds_sale,
        COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS available_qualifieds_rent,
        COUNT(NULL) AS available_qualifieds_sale,
        COUNT(NULL) AS available_qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
        COUNT(NULL) AS opportunities_sale,
        COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
        COUNT(NULL) AS first_listings_sale,
        COUNT(NULL) AS first_listings_hybrid,
        SUM(CAST(0 AS FLOAT)) AS cost_sale,
        SUM(CAST(0 AS FLOAT)) AS cost_rental,
        SUM(CAST(0 AS FLOAT)) AS tof_target,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_sale,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_sale,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_sale,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_sale,
        SUM(CAST(0 AS FLOAT)) AS budget_sale,
        SUM(CAST(0 AS FLOAT)) AS prospects_target_rental,
        SUM(CAST(0 AS FLOAT)) AS qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS available_qualifieds_target_rental,
        SUM(CAST(0 AS FLOAT)) AS opportunities_target_rental,
        SUM(CAST(0 AS FLOAT)) AS first_listings_target_rental,
        SUM(CAST(0 AS FLOAT)) AS budget_rental,
        SUM(prospects) AS prospects_target_unique,
        SUM(qualifieds) AS qualifieds_target_unique,
        SUM(opportunities) AS opportunities_target_unique,
        SUM(first_listings) AS first_listings_target_unique
    FROM 
        datalake_gsheets_clean.unique_volume_targets_day uvt 
    GROUP BY 
        1,2,3,4,5,6,7,8,9,10,11

),

campaign_origin AS (
    WITH counting AS(
        SELECT 
            utm_campaign,
            mkt_origin AS mkt_campaign_origin,
            COUNT(*) AS row_count
        FROM datalake_marketing_costs.daily_costs
        GROUP BY 1,2
    )
    
    SELECT
        utm_campaign,
        mkt_campaign_origin
    FROM counting
    QUALIFY ROW_NUMBER() OVER (PARTITION BY utm_campaign ORDER BY row_count DESC) = 1
)

SELECT
    date,
    city_group,
    affiliate_volumetry,
    CASE
        WHEN mkt_origin = 'PWA - Paid' THEN 'Owner PWA'
	WHEN mkt_origin = 'Owner PWA - Sale' THEN 'Owner PWA'
        ELSE mkt_origin
    END AS mkt_origin,
    mkt_channel,
    CASE
        WHEN mkt_origin = 'Owner PWA' AND mkt_channel = 'LeadEnrichment' THEN 'Organic'
        WHEN mkt_origin = 'Owner PWA' THEN mkt_channel
        WHEN mkt_origin  IN ('PWA - Paid', 'Owner PWA - Sale') THEN 'Paid'
        WHEN mkt_origin = 'Not Mapped' THEN 'Other'
        WHEN mkt_origin = 'Doorman Sale' THEN 'Doorman'
        WHEN mkt_origin = 'Indica Aí - Agents Sale' THEN 'Indica Aí - Agents'
        WHEN mkt_origin = 'Indica Aí - General Sale' THEN 'Indica Aí - General'
        WHEN mkt_origin IN ('CR', 'Autonomous Agent', 'Autonomuos Agent') THEN 'CIQ'
        ELSE mkt_origin
    END AS planning_mkt_channel,
    mkt_medium,
    mkt_source,
    mkt_campaign_origin, -- adding the origin cost of the campaign
    utm_campaign,
    utm_content,
    utm_term,
    NULLIF(origin_phone,'') AS origin_phone,
    SUM(tof_rent) AS tof_rent,
    SUM(tof_sale) AS tof_sale,
    SUM(leads_rent) AS leads_rent,
    SUM(leads_sale) AS leads_sale,
    SUM(leads_hybrid) AS leads_hybrid,
    SUM(prospects_rent) AS prospects_rent,
    SUM(prospects_sale) AS prospects_sale,
    SUM(prospects_hybrid) AS prospects_hybrid,
    SUM(qualifieds_rent) AS qualifieds_rent,
    SUM(qualifieds_sale) AS qualifieds_sale,
    SUM(qualifieds_hybrid) AS qualifieds_hybrid,
    SUM(available_qualifieds_rent) AS available_qualifieds_rent,
    SUM(available_qualifieds_sale) AS available_qualifieds_sale,
    SUM(available_qualifieds_hybrid) AS available_qualifieds_hybrid,
    SUM(opportunities_rent) AS opportunities_rent,
    SUM(opportunities_sale) AS opportunities_sale,
    SUM(opportunities_hybrid) AS opportunities_hybrid,
    SUM(first_listings_rent) AS first_listings_rent,
    SUM(first_listings_sale) AS first_listings_sale,
    SUM(first_listings_hybrid) AS first_listings_hybrid,
    SUM(CAST(cost_sale AS FLOAT)) AS cost_sale,
    SUM(CAST(cost_rental AS FLOAT)) AS cost_rental,
    SUM(CAST(REPLACE(tof_target,',','') AS FLOAT)) AS tof_target,
    SUM(CAST(prospects_target_sale AS FLOAT)) AS prospects_target_sale,
    SUM(CAST(qualifieds_target_sale AS FLOAT)) AS qualifieds_target_sale,
    SUM(CAST(available_qualifieds_target_sale AS FLOAT)) AS available_qualifieds_target_sale,
    SUM(CAST(opportunities_target_sale AS FLOAT)) AS opportunities_target_sale,
    SUM(CAST(first_listings_target_sale AS FLOAT)) AS first_listings_target_sale,
    SUM(CAST(budget_sale AS FLOAT)) AS budget_sale,
    SUM(CAST(prospects_target_rental AS FLOAT)) AS prospects_target_rental,
    SUM(CAST(qualifieds_target_rental AS FLOAT)) AS qualifieds_target_rental,
    SUM(CAST(available_qualifieds_target_rental AS FLOAT)) AS available_qualifieds_target_rental,
    SUM(CAST(opportunities_target_rental AS FLOAT)) AS opportunities_target_rental,
    SUM(CAST(first_listings_target_rental AS FLOAT)) AS first_listings_target_rental,
    SUM(CAST(budget_rental AS FLOAT)) AS budget_rental,
    SUM(prospects_target_unique) AS prospects_target_unique,
    SUM(qualifieds_target_unique) AS qualifieds_target_unique,
    SUM(opportunities_target_unique) AS opportunities_target_unique,
    SUM(first_listings_target_unique) AS first_listings_target_unique
FROM
    costs_targets_results_combined
JOIN
    dw_public.dim_date AS dd
    USING(sk_date)
LEFT JOIN
    campaign_origin USING(utm_campaign)
GROUP BY
    1,2,3,4,5,6,7,8,9,10,11,12,13
