WITH
-------------------------------------
-- Affiliates NAUS & OAUS --
-------------------------------------
naus_oaus AS (
WITH dist_affiliates AS (
    SELECT DISTINCT 
        COALESCE(dua.marketing_city_group, 'Not Mapped') AS city_group,
        COALESCE(dua.mkt_origin, '') AS mkt_origin,
        COALESCE(dua.mkt_channel, '') AS mkt_channel,
        COALESCE(dua.mkt_medium, '') AS mkt_medium,
        COALESCE(dua.mkt_source, '') AS mkt_source,
        COALESCE(dua.tracking_campaign, '') AS utm_campaign,
        COALESCE(dua.tracking_content, '') AS utm_content,
        COALESCE(dua.tracking_term, '') AS utm_term,
        dua.sk_user AS affiliates,
        dua.ts_joined_program,
        MIN(dt_prospect.date) AS min_prospect_date
	FROM
		dim_user_affiliate dua
    LEFT JOIN datamarts.lead_listing_flows f
        ON f.sk_user_lead_affiliate = dua.sk_user
    LEFT JOIN public.dim_date AS dt_lead
        ON f.sk_lead_date = dt_lead.sk_date
    LEFT JOIN public.dim_date AS dt_prospect
        ON f.sk_prospect_date = dt_prospect.sk_date
    LEFT JOIN public.dim_date AS dt_qualified
        ON f.sk_qualified_date = dt_qualified.sk_date
    WHERE 
        dua.type = 'Standard'
        AND f.sk_prospect_date <> -1
    GROUP BY 
        1,2,3,4,5,6,7,8,9,10
)
SELECT 
    min_prospect_date AS date,
    city_group,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    utm_campaign,
    utm_content,
    utm_term,
    COUNT(DISTINCT CASE WHEN min_prospect_date <= DATE(ts_joined_program) + 30 THEN affiliates END) AS naus,
    COUNT(DISTINCT CASE WHEN min_prospect_date > DATE(ts_joined_program) + 30 THEN affiliates END) AS oaus
FROM    
    dist_affiliates
GROUP BY 
    1,2,3,4,5,6,7,8,9
),

-------------------------------------
-- Affiliates Never Active --
-------------------------------------
cluster_count as(
    SELECT 
        month_start,
        COUNT(CASE WHEN cluster IN('Nunca Ativo em Lead','Nunca Ativo em Prospect') THEN 1 END) as nunca_ativo_count
    FROM 
	datamarts.affiliates_clusters 
    GROUP BY 1
),

affiliates_acquisition_funnel as (
-----------------------------------
-- Affiliates Acquisition Funnel --
-----------------------------------
    SELECT
        NULLIF(dua.ts_joined_program,NULL)::DATE AS date,
        COALESCE(dua.marketing_city_group, 'Not Mapped') AS city_group,
        COALESCE(dua.mkt_origin, '') AS mkt_origin,
        COALESCE(dua.mkt_channel, '') AS mkt_channel,
        COALESCE(dua.mkt_medium, '') AS mkt_medium,
        COALESCE(dua.mkt_source, '') AS mkt_source,
        COALESCE(dua.tracking_campaign, '') AS utm_campaign,
        COALESCE(dua.tracking_content, '') AS utm_content,
        COALESCE(dua.tracking_term, '') AS utm_term,
        COUNT(DISTINCT dua.sk_user) AS affiliates,
        COUNT(DISTINCT CASE WHEN dt_lead.date <= DATE(dua.ts_joined_program) + 1 THEN dua.sk_user END) AS active_affiliate_lead_d1,
        COUNT(DISTINCT CASE WHEN dt_prospect.date <= DATE(dua.ts_joined_program) + 1 THEN dua.sk_user END) AS active_affiliate_prospect_d1,
        COUNT(DISTINCT CASE WHEN dt_qualified.date <= DATE(dua.ts_joined_program) + 1 THEN dua.sk_user END) AS active_affiliate_qualified_d1,
        COUNT(DISTINCT CASE WHEN dt_prospect.date <= DATE(dua.ts_joined_program) + 30 THEN dua.sk_user END) AS naus,
        COUNT(DISTINCT CASE WHEN dt_prospect.date > DATE(dua.ts_joined_program) + 30 THEN dua.sk_user END) AS oaus,
        --COUNT(DISTINCT CASE WHEN sk_lead_dateIS NULL AND sk_prospect_date IS NULL + 30 THEN dua.sk_user END) AS never_activated_lead_prospect,
        COUNT(DISTINCT CASE WHEN sk_lead_date > 0 AND f.context_lead = 'Rent' THEN 1 END) AS leads_rent,
		COUNT(DISTINCT CASE WHEN sk_lead_date > 0 AND f.context_lead = 'Sale' THEN 1 END) AS leads_sale,
		COUNT(DISTINCT CASE WHEN sk_lead_date > 0 AND (f.context_lead = 'Hybrid' OR f.context_lead = NULL) THEN 1 END) AS leads_hybrid,
        COUNT(DISTINCT CASE WHEN sk_prospect_date > 0 AND f.context_prospect= 'Rent' THEN 1 END) AS prospects_rent,
		COUNT(DISTINCT CASE WHEN sk_prospect_date > 0 AND f.context_prospect = 'Sale' THEN 1 END) AS prospects_sale,
		COUNT(DISTINCT CASE WHEN sk_prospect_date > 0 AND (f.context_prospect = 'Hybrid' OR f.context_prospect = NULL) THEN 1 END) AS prospects_hybrid,
        COUNT(DISTINCT CASE WHEN sk_qualified_date > 0 AND f.context_qualified = 'Rent' THEN 1 END) AS qualifieds_rent,
		COUNT(DISTINCT CASE WHEN sk_qualified_date > 0 AND f.context_qualified = 'Sale' THEN 1 END) AS qualifieds_sale,
		COUNT(DISTINCT CASE WHEN sk_qualified_date > 0 AND (f.context_qualified = 'Hybrid' OR f.context_qualified = NULL) THEN 1 END) AS qualifieds_hybrid,
        COUNT(DISTINCT CASE WHEN sk_opportunity_date > 0 AND f.context_opportunity = 'Rent' THEN 1 END) AS opportunities_rent,
		COUNT(DISTINCT CASE WHEN sk_opportunity_date > 0 AND f.context_opportunity = 'Sale' THEN 1 END) AS opportunities_sale,
		COUNT(DISTINCT CASE WHEN sk_opportunity_date > 0 AND (f.context_opportunity = 'Hybrid' OR f.context_opportunity = NULL) THEN 1 END) AS opportunities_hybrid,
        COUNT(DISTINCT CASE WHEN f.sk_first_listing_date > 0 AND f.context_first_listing = 'Rent' THEN 1 END) AS first_listings_rent,
		COUNT(DISTINCT CASE WHEN f.sk_first_listing_date > 0 AND f.context_first_listing = 'Sale' THEN 1 END) AS first_listings_sale,
		COUNT(DISTINCT CASE WHEN f.sk_first_listing_date > 0 AND (f.context_first_listing = 'Hybrid' OR f.context_first_listing = NULL) THEN 1 END) AS first_listings_hybrid,
        SUM(0::FLOAT) AS cost,
        SUM(0::FLOAT) AS active_affiliate_prospect_d1_target,
        SUM(0::FLOAT) AS budget,
        SUM(0::FLOAT) AS target_nu,
        SUM(0::FLOAT) AS target_oau,
        SUM(0::FLOAT) AS new_target_nau 
	FROM
		dim_user_affiliate dua
    LEFT JOIN datamarts.lead_listing_flows f
        ON f.sk_user_lead_affiliate = dua.sk_user
    LEFT JOIN public.dim_date AS dt_lead
        ON f.sk_lead_date = dt_lead.sk_date
    LEFT JOIN public.dim_date AS dt_prospect
        ON f.sk_prospect_date = dt_prospect.sk_date
    LEFT JOIN public.dim_date AS dt_qualified
        ON f.sk_qualified_date = dt_qualified.sk_date
    WHERE dua.type = 'Standard'
    GROUP BY 1,2,3,4,5,6,7,8,9
    
UNION ALL
-------------------------------------
-- Affiliates Acquisition Investment --
-------------------------------------

    SELECT
        dd.date AS date ,
        COALESCE(mkt.city_group, 'Not Mapped') AS city_group,
		COALESCE(mkt.mkt_origin, '') AS mkt_origin,
		COALESCE(mkt.mkt_channel, '') AS mkt_channel,
		COALESCE(mkt.mkt_medium, '') AS mkt_medium,
		COALESCE(mkt.mkt_source, '') AS mkt_source,
		COALESCE(mkt.utm_campaign, '') AS utm_campaign,
		COALESCE(mkt.utm_content, '') AS utm_content,
		COALESCE(mkt.utm_term, '') AS utm_term,
		COUNT(NULL) AS affiliates,
        COUNT(NULL) AS active_affiliate_lead_d1,
        COUNT(NULL) AS active_affiliate_prospect_d1,
        COUNT(NULL) AS active_affiliate_qualified_d1,
        COUNT(NULL) AS naus,
        COUNT(NULL) AS oaus,
        COUNT(NULL) AS leads_rent,
		COUNT(NULL) AS leads_sale,
		COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
		COUNT(NULL) AS prospects_sale,
		COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
		COUNT(NULL) AS qualifieds_sale,
		COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
		COUNT(NULL) AS opportunities_sale,
		COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
		COUNT(NULL) AS first_listings_sale,
		COUNT(NULL) AS first_listings_hybrid,
        SUM(coalesce(cost,0)) as cost,
        SUM(0::FLOAT) AS active_affiliate_prospect_d1_target,
        SUM(0::FLOAT) AS budget,
        SUM(0::FLOAT) AS target_nu,
        SUM(0::FLOAT) AS target_oau,
        SUM(0::FLOAT) AS new_target_nau 
    FROM
        datalake_marketing_costs_prod.daily_costs mkt
    JOIN public.dim_date dd
        ON dd.sk_date =  mkt.id_date
    WHERE mkt.funnel_side IN ('supply','affiliates')
        AND mkt.mkt_origin = 'Indica Aí - General'
        AND mkt.mkt_channel IN ('Paid', 'Organic')
    GROUP BY 1,2,3,4,5,6,7,8,9

UNION ALL

    (WITH
    ia_affiliate_commission_costs AS (
        WITH
        commission_costs AS (
            SELECT
                DISTINCT f.sk_rh_accounting_entry,
                d.mkt_origin,
                d.city_group,
                f.sk_date,
                d.comission_type AS source,
                d.cost_center_code,
                f.cost
            FROM
                quintoandar.fact_affiliate_costs f
            LEFT JOIN
                quintoandar.dim_affiliate_cost d
                ON f.sk_rh_accounting_entry = d.sk_rh_accounting_entry
            )
            SELECT
                cc.sk_date AS sk_date ,
                cc.city_group AS city_group,
                COALESCE(cc.mkt_origin, '') AS mkt_origin,
                NULL::TEXT AS mkt_channel,
                NULL::TEXT AS mkt_medium,
                COALESCE(cc.source, '') AS mkt_source,
                NULL::TEXT AS utm_campaign,
                NULL::TEXT AS utm_content,
                NULL::TEXT AS utm_term,
                COUNT(NULL) AS affiliates,
                COUNT(NULL) AS active_affiliate_lead_d1,
                COUNT(NULL) AS active_affiliate_prospect_d1,
                COUNT(NULL) AS active_affiliate_qualified_d1,
                COUNT(NULL) AS naus,
                COUNT(NULL) AS oaus,
                COUNT(NULL) AS leads_rent,
        		COUNT(NULL) AS leads_sale,
        		COUNT(NULL) AS leads_hybrid,
                COUNT(NULL) AS prospects_rent,
        		COUNT(NULL) AS prospects_sale,
        		COUNT(NULL) AS prospects_hybrid,
                COUNT(NULL) AS qualifieds_rent,
        		COUNT(NULL) AS qualifieds_sale,
        		COUNT(NULL) AS qualifieds_hybrid,
                COUNT(NULL) AS opportunities_rent,
        		COUNT(NULL) AS opportunities_sale,
        		COUNT(NULL) AS opportunities_hybrid,
                COUNT(NULL) AS first_listings_rent,
        		COUNT(NULL) AS first_listings_sale,
        		COUNT(NULL) AS first_listings_hybrid,
                SUM(cc.cost) AS cost,
                SUM(0::FLOAT) AS active_affiliate_prospect_d1_target,
                SUM(0::FLOAT) AS budget,
                SUM(0::FLOAT) AS target_nu,
                SUM(0::FLOAT) AS target_oau,
                SUM(0::FLOAT) AS new_target_nau 
            FROM
                commission_costs cc
            WHERE cc.sk_date >= 20210125
                AND cc.source = 'Commission MGM'
            GROUP BY 1,2,3,4,5,6,7,8,9
        ),
        ia_fact_affiliate AS (
            SELECT
                sk_date AS sk_date ,
                city_group AS city_group ,
                mkt_origin AS mkt_origin,
                NULL::TEXT AS mkt_channel,
                NULL::TEXT AS mkt_medium,
                'Commission MGM' AS mkt_source,
                NULL::TEXT AS utm_campaign,
                NULL::TEXT AS utm_content,
                NULL::TEXT AS utm_term,
                COUNT(NULL) AS affiliates,
                COUNT(NULL) AS active_affiliate_lead_d1,
                COUNT(NULL) AS active_affiliate_prospect_d1,
                COUNT(NULL) AS active_affiliate_qualified_d1,
                COUNT(NULL) AS naus,
                COUNT(NULL) AS oaus,
                COUNT(NULL) AS leads_rent,
        		COUNT(NULL) AS leads_sale,
        		COUNT(NULL) AS leads_hybrid,
                COUNT(NULL) AS prospects_rent,
        		COUNT(NULL) AS prospects_sale,
        		COUNT(NULL) AS prospects_hybrid,
                COUNT(NULL) AS qualifieds_rent,
        		COUNT(NULL) AS qualifieds_sale,
        		COUNT(NULL) AS qualifieds_hybrid,
                COUNT(NULL) AS opportunities_rent,
        		COUNT(NULL) AS opportunities_sale,
        		COUNT(NULL) AS opportunities_hybrid,
                COUNT(NULL) AS first_listings_rent,
        		COUNT(NULL) AS first_listings_sale,
        		COUNT(NULL) AS first_listings_hybrid,
                SUM(commission_mgm) AS cost,
                SUM(0::FLOAT) AS active_affiliate_prospect_d1_target,
                SUM(0::FLOAT) AS budget,
                SUM(0::FLOAT) AS target_nu,
                SUM(0::FLOAT) AS target_oau,
                SUM(0::FLOAT) AS new_target_nau 
            FROM
                marketing.fact_affiliate_daily_cost_attributions
            WHERE sk_date < 20210125
            GROUP BY 1,2,3,4,5,6,7,8,9
            ),
            ia_total_cost AS (
                SELECT * FROM ia_fact_affiliate
                UNION ALL
                SELECT * FROM ia_affiliate_commission_costs
                )
                SELECT
                    dd.date,
                    iac.city_group,
                    iac.mkt_origin,
                    CASE
                        WHEN iac.mkt_source = 'Commission MGM' THEN 'Paid'
                        ELSE iac.mkt_channel
                    END AS mkt_channel,
                    iac.mkt_medium,
                    CASE
                        WHEN iac.mkt_source = 'Commission MGM' THEN 'MGM'
                        ELSE iac.mkt_source
                    END AS mkt_source,
                    iac.utm_campaign,
                    iac.utm_content,
                    iac.utm_term,
                    SUM(iac.affiliates) AS affiliates,
                    SUM(iac.active_affiliate_lead_d1) AS active_affiliate_lead_d1,
                    SUM(iac.active_affiliate_prospect_d1) AS active_affiliate_prospect_d1,
                    SUM(iac.active_affiliate_qualified_d1) AS active_affiliate_qualified_d1,
                    SUM(iac.naus) AS naus,
                    SUM(iac.oaus) AS oaus,
                    SUM(iac.leads_rent) AS leads_rent,
            		SUM(iac.leads_sale) AS leads_sale,
            		SUM(iac.leads_hybrid) AS leads_hybrid,
                    SUM(iac.prospects_rent) AS prospects_rent,
            		SUM(iac.prospects_sale) AS prospects_sale,
            		SUM(iac.prospects_hybrid) AS prospects_hybrid,
                    SUM(iac.qualifieds_rent) AS qualifieds_rent,
            		SUM(iac.qualifieds_sale) AS qualifieds_sale,
            		SUM(iac.qualifieds_hybrid) AS qualifieds_hybrid,
                    SUM(iac.opportunities_rent) AS opportunities_rent,
            		SUM(iac.opportunities_sale) AS opportunities_sale,
            		SUM(iac.opportunities_hybrid) AS opportunities_hybrid,
                    SUM(iac.first_listings_rent) AS first_listings_rent,
            		SUM(iac.first_listings_sale) AS first_listings_sale,
            		SUM(iac.first_listings_hybrid) AS first_listings_hybrid,
                    SUM(iac.cost) AS cost,
                    SUM(iac.active_affiliate_prospect_d1_target) AS active_affiliate_prospect_d1_target,
                    SUM(iac.budget) AS budget,
                    SUM(iac.target_nu) AS target_nu,
                    SUM(iac.target_oau) AS target_oau,
                    SUM(iac.new_target_nau) AS new_target_nau 
                FROM
                    ia_total_cost iac
                LEFT JOIN dim_date dd
                    ON dd.sk_date = iac.sk_date
                WHERE iac.cost IS NOT NULL
                GROUP BY 1,2,3,4,5,6,7,8,9,iac.cost
                HAVING cost>0
    )

UNION ALL

-------------------------------------
-- Affiliates Acquisition Targets --
-------------------------------------
    SELECT
        DATE(tgt.data) as date,
        NULL::TEXT AS city_group,
        tgt.mkt_origin AS mkt_origin,
        tgt.mkt_channel AS mkt_channel,
        tgt.mkt_medium AS mkt_medium,
        tgt.mkt_source AS mkt_source,
        NULL::TEXT AS utm_campaign,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS utm_term,
        COUNT(NULL) AS affiliates,
        COUNT(NULL) AS active_affiliate_lead_d1,
        COUNT(NULL) AS active_affiliate_prospect_d1,
        COUNT(NULL) AS active_affiliate_qualified_d1,
        COUNT(NULL) AS naus,
        COUNT(NULL) AS oaus,
        COUNT(NULL) AS leads_rent,
		COUNT(NULL) AS leads_sale,
		COUNT(NULL) AS leads_hybrid,
        COUNT(NULL) AS prospects_rent,
		COUNT(NULL) AS prospects_sale,
		COUNT(NULL) AS prospects_hybrid,
        COUNT(NULL) AS qualifieds_rent,
		COUNT(NULL) AS qualifieds_sale,
		COUNT(NULL) AS qualifieds_hybrid,
        COUNT(NULL) AS opportunities_rent,
		COUNT(NULL) AS opportunities_sale,
		COUNT(NULL) AS opportunities_hybrid,
        COUNT(NULL) AS first_listings_rent,
		COUNT(NULL) AS first_listings_sale,
		COUNT(NULL) AS first_listings_hybrid,
        SUM(0::FLOAT) AS cost,
        SUM(tgt.target_nau::FLOAT) AS active_affiliate_prospect_d1_target,
        SUM(tgt.budget::FLOAT) AS budget,
        SUM(tgt.target_nu::FLOAT) AS target_nu,
        SUM(tgt.target_oau::FLOAT) AS target_oau,
        SUM(tgt.new_target_nau::FLOAT) AS new_target_nau 
    FROM
        datalake_gsheets_clean_prod.affiliates_acquisition_targets tgt
    GROUP BY 1,2,3,4,5,6,7,8,9
)
SELECT
    aaf.date AS date,
    aaf.city_group AS city_group,
    aaf.mkt_origin AS mkt_origin,
    aaf.mkt_channel AS mkt_channel,
    aaf.mkt_medium AS mkt_medium,
    aaf.mkt_source AS mkt_source,
    aaf.utm_campaign AS utm_campaign,
    aaf.utm_content AS utm_content,
    aaf.utm_term AS utm_term,
    cc.nunca_ativo_count,
    SUM(aaf.affiliates) AS affiliates,
    SUM(aaf.active_affiliate_lead_d1) AS active_affiliate_lead_d1,
    SUM(aaf.active_affiliate_prospect_d1) AS active_affiliate_prospect_d1,
    SUM(aaf.active_affiliate_qualified_d1) AS active_affiliate_qualified_d1,
    ISNULL(SUM(no.naus),0) AS naus,
    ISNULL(SUM(no.oaus),0) AS oaus,
    SUM(no.naus) + SUM(no.oaus) AS faus,
    SUM(aaf.leads_rent) AS leads_rent,
	SUM(aaf.leads_sale) AS leads_sale,
	SUM(aaf.leads_hybrid) AS leads_hybrid,
    SUM(aaf.prospects_rent) AS prospects_rent,
	SUM(aaf.prospects_sale) AS prospects_sale,
	SUM(aaf.prospects_hybrid) AS prospects_hybrid,
    SUM(aaf.qualifieds_rent) AS qualifieds_rent,
	SUM(aaf.qualifieds_sale) AS qualifieds_sale,
	SUM(aaf.qualifieds_hybrid) AS qualifieds_hybrid,
    SUM(aaf.opportunities_rent) AS opportunities_rent,
	SUM(aaf.opportunities_sale) AS opportunities_sale,
	SUM(aaf.opportunities_hybrid) AS opportunities_hybrid,
    SUM(aaf.first_listings_rent) AS first_listings_rent,
	SUM(aaf.first_listings_sale) AS first_listings_sale,
	SUM(aaf.first_listings_hybrid) AS first_listings_hybrid,
    SUM(aaf.cost::FLOAT) AS cost,
    ISNULL(SUM(aaf.cost::FLOAT)/(SUM(no.naus) + SUM(no.oaus)),0) AS cpfau,
    SUM(aaf.active_affiliate_prospect_d1_target::FLOAT) AS active_affiliate_prospect_d1_target,
    SUM(aaf.budget::FLOAT) AS budget,
    SUM(aaf.target_nu::FLOAT) AS target_nu,
    SUM(aaf.target_oau::FLOAT) AS target_oau,
    SUM(aaf.new_target_nau::FLOAT) AS new_target_nau 
FROM
    affiliates_acquisition_funnel aaf
LEFT JOIN naus_oaus no
    ON no.date = aaf.date
    AND no.city_group = aaf.city_group
    AND no.mkt_origin = aaf.mkt_origin
    AND no.mkt_channel = aaf.mkt_channel
    AND no.mkt_medium = aaf.mkt_medium 
    AND no.mkt_source = aaf.mkt_source
    AND no.utm_campaign = aaf.utm_campaign
    AND no.utm_content = aaf.utm_content
    AND no.utm_term = aaf.utm_term
LEFT JOIN cluster_count cc
    ON DATE_TRUNC('month', aaf.date) = cc.month_start
GROUP BY 1,2,3,4,5,6,7,8,9,10