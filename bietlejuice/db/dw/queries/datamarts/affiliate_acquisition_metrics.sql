WITH
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
        COUNT(CASE WHEN f.sk_lead_date > 0 THEN 1 END) AS leads,
        COUNT(CASE WHEN f.sk_prospect_date > 0 THEN 1 END) AS prospects,
        COUNT(CASE WHEN f.sk_qualified_date > 0 THEN 1 END) AS qualifieds,
        COUNT(CASE WHEN f.sk_opportunity_date > 0 THEN 1 END) AS opportunities,
        COUNT(CASE WHEN f.sk_first_listing_date > 0 THEN 1 END) AS first_listings,
        SUM(0::FLOAT) AS cost,
        SUM(0::FLOAT) AS active_affiliate_prospect_d1_target,
        SUM(0::FLOAT) AS budget
	FROM
		dim_user_affiliate dua
    LEFT JOIN fact_house_listing_flows f
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
        COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS listings,
        SUM(coalesce(cost,0)) as cost,
        SUM(0::FLOAT) AS active_affiliate_prospect_d1_target,
        SUM(0::FLOAT) AS budget
    FROM
        marketing.fact_marketing_daily_costs mkt
    JOIN public.dim_date dd
        ON dd.sk_date =  mkt.sk_date
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
                COUNT(NULL) AS leads,
                COUNT(NULL) AS prospects,
                COUNT(NULL) AS qualifieds,
                COUNT(NULL) AS opportunities,
                COUNT(NULL) AS first_listings,
                SUM(cc.cost) AS cost,
                SUM(0::FLOAT) AS active_affiliate_prospect_d1_target,
                SUM(0::FLOAT) AS budget
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
                COUNT(NULL) AS leads,
                COUNT(NULL) AS prospects,
                COUNT(NULL) AS qualifieds,
                COUNT(NULL) AS opportunities,
                COUNT(NULL) AS first_listings,
                SUM(commission_mgm) AS cost,
                SUM(0::FLOAT) AS active_affiliate_prospect_d1_target,
                SUM(0::FLOAT) AS budget
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
                    SUM(iac.leads) AS leads,
                    SUM(iac.prospects) AS prospects,
                    SUM(iac.qualifieds) AS qualifieds,
                    SUM(iac.opportunities) AS opportunities,
                    SUM(iac.first_listings) AS first_listings,
                    SUM(iac.cost) AS cost,
                    SUM(iac.active_affiliate_prospect_d1_target) AS active_affiliate_prospect_d1_target,
                    SUM(iac.budget) AS budget
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
        COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        SUM(0::FLOAT) AS cost,
        SUM(tgt.target_nau::FLOAT) AS active_affiliate_prospect_d1_target,
        SUM(tgt.budget::FLOAT) AS budget
    FROM
        datalake_raw.gsheets_marketing_affiliates_acquisition_targets tgt
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
    SUM(aaf.affiliates) AS affiliates,
    SUM(aaf.active_affiliate_lead_d1) AS active_affiliate_lead_d1,
    SUM(aaf.active_affiliate_prospect_d1) AS active_affiliate_prospect_d1,
    SUM(aaf.active_affiliate_qualified_d1) AS active_affiliate_qualified_d1,
    SUM(aaf.leads) AS leads,
    SUM(aaf.prospects) AS prospects,
    SUM(aaf.qualifieds) AS qualifieds,
    SUM(aaf.opportunities) AS opportunities,
    SUM(aaf.first_listings) AS first_listings,
    SUM(aaf.cost::FLOAT) AS cost,
    SUM(aaf.active_affiliate_prospect_d1_target::FLOAT) AS active_affiliate_prospect_d1_target,
    SUM(aaf.budget::FLOAT) AS budget
FROM
    affiliates_acquisition_funnel aaf
GROUP BY 1,2,3,4,5,6,7,8,9
