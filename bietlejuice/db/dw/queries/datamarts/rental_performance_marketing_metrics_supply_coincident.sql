WITH
listings_sale AS (
  ----------------------------------------------------------------------------------------
  -- Supply ForSale Listings for hybrid volume measurement (listed in the same month) --
  ----------------------------------------------------------------------------------------
  SELECT DISTINCT
    dd.month_start,
    SUBSTRING(f.sk_house_listing, 1, 9) AS id_house
  FROM
    sale.fact_listing_flows AS f
      JOIN dim_date AS dd
        ON f.sk_first_listing_date = dd.sk_date
  WHERE
    f.sk_first_listing_date >= 20200101
    AND f.sk_house_listing > 0
),
costs_targets_results_combined AS (
  ---------------------------------
  -- Supply ForRental Leads Volume --
  ---------------------------------
		SELECT
		f.sk_lead_date AS sk_date,
		COALESCE(dr.city_group, 'Not Mapped') AS city_group,
		COALESCE(f.mkt_origin,'') AS mkt_origin,
		COALESCE(f.mkt_channel,'') AS mkt_channel,
		COALESCE(f.mkt_medium,'') AS mkt_medium,
		COALESCE(f.mkt_source,'') AS mkt_source,
		COALESCE(dl.utm_campaign,'') AS utm_campaign,
		COALESCE(dl.utm_content,'') AS utm_content,
		COALESCE(dl.utm_term,'') AS utm_term,
		COALESCE(p.origin_phone,'') AS origin_phone,
		CASE
	        WHEN LOWER(dl.utm_campaign) ~ '(sale|girafa|vender)' OR f.sk_user_lead_affiliate in (912255, 360754, 1711931, 2257503)
	            THEN 'Sale'
	        WHEN f.mkt_origin IN ('Indica Aí - Agents', 'Doorman', 'Indica Aí - General') OR LOWER(dl.utm_campaign) LIKE '%hybrid%'
	            THEN 'Hybrid'
            WHEN ((dl.utm_campaign IS NULL OR dl.utm_campaign = '') AND LOWER(f.mkt_channel) NOT LIKE '%paid%') OR (LOWER(dl.utm_campaign) LIKE '%branded%' AND LOWER(dl.utm_campaign) NOT LIKE '%non-branded%')
	            THEN 'Organic'
	        ELSE 'Rental'
	    END AS campaign_context,
	    'Rental' AS business_context,
		COUNT(DISTINCT CASE WHEN f.sk_lead_date > 0 THEN f.sk_house_listing_flow ELSE NULL END) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(0::FLOAT) AS cost,
        SUM(0::FLOAT) AS prospects_target,
        SUM(0::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(0::FLOAT) AS budget
	FROM
		fact_house_listing_flows f
		JOIN dim_lead dl
			ON dl.sk_lead = f.sk_lead
		JOIN dim_region dr
			ON f.sk_region = dr.sk_region
        LEFT JOIN datalake_wololo_clean_prod.prospect p
            ON p.id_reference = f.sk_lead
	GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12

  UNION ALL

  -------------------------------------
  -- Supply ForRental Prospects Volume --
  -------------------------------------
	SELECT
		f.sk_prospect_date AS sk_date,
		COALESCE(dr.city_group, 'Not Mapped') AS city_group,
		COALESCE(f.mkt_origin,'') AS mkt_origin,
		COALESCE(f.mkt_channel,'') AS mkt_channel,
		COALESCE(f.mkt_medium,'') AS mkt_medium,
		COALESCE(f.mkt_source,'') AS mkt_source,
		COALESCE(dl.utm_campaign,'') AS utm_campaign,
		COALESCE(dl.utm_content,'') AS utm_content,
		COALESCE(dl.utm_term,'') AS utm_term,
		COALESCE(p.origin_phone,'') AS origin_phone,
		CASE
	        WHEN LOWER(dl.utm_campaign) ~ '(sale|girafa|vender)' OR f.sk_user_lead_affiliate in (912255, 360754, 1711931, 2257503)
	            THEN 'Sale'
	        WHEN f.mkt_origin IN ('Indica Aí - Agents', 'Doorman', 'Indica Aí - General') OR LOWER(dl.utm_campaign) LIKE '%hybrid%'
	            THEN 'Hybrid'
            WHEN ((dl.utm_campaign IS NULL OR dl.utm_campaign = '') AND LOWER(f.mkt_channel) NOT LIKE '%paid%') OR (LOWER(dl.utm_campaign) LIKE '%branded%' AND LOWER(dl.utm_campaign) NOT LIKE '%non-branded%')
	            THEN 'Organic'
	        ELSE 'Rental'
	    END AS campaign_context,
	    'Rental' AS business_context,
		COUNT(NULL) AS leads,
        COUNT(DISTINCT CASE WHEN f.sk_prospect_date > 0 THEN f.sk_house_listing_flow ELSE NULL END) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(0::FLOAT) AS cost,
        SUM(0::FLOAT) AS prospects_target,
        SUM(0::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(0::FLOAT) AS budget
	FROM
		fact_house_listing_flows f
		JOIN dim_lead dl
			ON dl.sk_lead = f.sk_lead
		JOIN dim_region dr
			ON f.sk_region = dr.sk_region
        LEFT JOIN datalake_wololo_clean_prod.prospect p
            ON p.id_reference = f.sk_lead
	GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12

  UNION ALL

  --------------------------------------
  -- Supply ForRental Qualifieds Volume --
  --------------------------------------
	SELECT
		f.sk_qualified_date AS sk_date,
		COALESCE(dr.city_group, 'Not Mapped') AS city_group,
		COALESCE(f.mkt_origin,'') AS mkt_origin,
		COALESCE(f.mkt_channel,'') AS mkt_channel,
		COALESCE(f.mkt_medium,'') AS mkt_medium,
		COALESCE(f.mkt_source,'') AS mkt_source,
		COALESCE(dl.utm_campaign,'') AS utm_campaign,
		COALESCE(dl.utm_content,'') AS utm_content,
		COALESCE(dl.utm_term,'') AS utm_term,
		COALESCE(p.origin_phone,'') AS origin_phone,
		CASE
	        WHEN LOWER(dl.utm_campaign) ~ '(sale|girafa|vender)' OR f.sk_user_lead_affiliate in (912255, 360754, 1711931, 2257503)
	            THEN 'Sale'
	        WHEN f.mkt_origin IN ('Indica Aí - Agents', 'Doorman', 'Indica Aí - General') OR LOWER(dl.utm_campaign) LIKE '%hybrid%'
	            THEN 'Hybrid'
            WHEN ((dl.utm_campaign IS NULL OR dl.utm_campaign = '') AND LOWER(f.mkt_channel) NOT LIKE '%paid%') OR (LOWER(dl.utm_campaign) LIKE '%branded%' AND LOWER(dl.utm_campaign) NOT LIKE '%non-branded%')
	            THEN 'Organic'
	        ELSE 'Rental'
	    END AS campaign_context,
	    'Rental' AS business_context,
		COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(DISTINCT CASE WHEN f.sk_qualified_date > 0 THEN f.sk_house_listing_flow ELSE NULL END) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(0::FLOAT) AS cost,
        SUM(0::FLOAT) AS prospects_target,
        SUM(0::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(0::FLOAT) AS budget
	FROM
		fact_house_listing_flows f
		JOIN dim_lead dl
			ON dl.sk_lead = f.sk_lead
		JOIN dim_region dr
			ON f.sk_region = dr.sk_region
        LEFT JOIN datalake_wololo_clean_prod.prospect p
            ON p.id_reference = f.sk_lead
	GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12

  UNION ALL

  -----------------------------------------
  -- Supply ForRental Opportunities Volume --
  -----------------------------------------
	SELECT
		f.sk_opportunity_date AS sk_date,
		COALESCE(dr.city_group, 'Not Mapped') AS city_group,
		COALESCE(f.mkt_origin,'') AS mkt_origin,
		COALESCE(f.mkt_channel,'') AS mkt_channel,
		COALESCE(f.mkt_medium,'') AS mkt_medium,
		COALESCE(f.mkt_source,'') AS mkt_source,
		COALESCE(dl.utm_campaign,'') AS utm_campaign,
		COALESCE(dl.utm_content,'') AS utm_content,
		COALESCE(dl.utm_term,'') AS utm_term,
		COALESCE(p.origin_phone,'') AS origin_phone,
		CASE
	        WHEN LOWER(dl.utm_campaign) ~ '(sale|girafa|vender)' OR f.sk_user_lead_affiliate in (912255, 360754, 1711931, 2257503)
	            THEN 'Sale'
	        WHEN f.mkt_origin IN ('Indica Aí - Agents', 'Doorman', 'Indica Aí - General') OR LOWER(dl.utm_campaign) LIKE '%hybrid%'
	            THEN 'Hybrid'
            WHEN ((dl.utm_campaign IS NULL OR dl.utm_campaign = '') AND LOWER(f.mkt_channel) NOT LIKE '%paid%') OR (LOWER(dl.utm_campaign) LIKE '%branded%' AND LOWER(dl.utm_campaign) NOT LIKE '%non-branded%')
	            THEN 'Organic'
	        ELSE 'Rental'
	    END AS campaign_context,
	    'Rental' AS business_context,
		COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(DISTINCT CASE WHEN f.sk_opportunity_date > 0 THEN f.sk_house_listing_flow ELSE NULL END) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(0::FLOAT) AS cost,
        SUM(0::FLOAT) AS prospects_target,
        SUM(0::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(0::FLOAT) AS budget
	FROM
		fact_house_listing_flows f
		JOIN dim_lead dl
			ON dl.sk_lead = f.sk_lead
		JOIN dim_region dr
			ON f.sk_region = dr.sk_region
        LEFT JOIN datalake_wololo_clean_prod.prospect p
            ON p.id_reference = f.sk_lead
	GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12

  UNION ALL

  ------------------------------------------
  -- Supply ForRental First Listings Volume --
  ------------------------------------------
    SELECT
        f.sk_first_listing_date AS sk_date,
        COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        COALESCE(f.mkt_origin,'') AS mkt_origin,
        COALESCE(f.mkt_channel,'') AS mkt_channel,
        COALESCE(f.mkt_medium,'') AS mkt_medium,
        COALESCE(f.mkt_source,'') AS mkt_source,
        COALESCE(dl.utm_campaign,'') AS utm_campaign,
        COALESCE(dl.utm_content,'') AS utm_content,
        COALESCE(dl.utm_term,'') AS utm_term,
        COALESCE(p.origin_phone,'') AS origin_phone,
        CASE
            WHEN LOWER(dl.utm_campaign) ~ '(sale|girafa|vender)' OR f.sk_user_lead_affiliate in (912255, 360754, 1711931, 2257503)
                THEN 'Sale'
            WHEN f.mkt_origin IN ('Indica Aí - Agents', 'Doorman', 'Indica Aí - General') OR LOWER(dl.utm_campaign) LIKE '%hybrid%'
                THEN 'Hybrid'
            WHEN ((dl.utm_campaign IS NULL OR dl.utm_campaign = '') AND LOWER(f.mkt_channel) NOT LIKE '%paid%') OR (LOWER(dl.utm_campaign) LIKE '%branded%' AND LOWER(dl.utm_campaign) NOT LIKE '%non-branded%')
                THEN 'Organic'
            ELSE 'Rental'
        END AS campaign_context,
        'Rental' AS business_context,
        COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(DISTINCT CASE WHEN f.sk_first_listing_date > 0 THEN f.sk_house_listing_flow ELSE NULL END) AS first_listings,
        COUNT(DISTINCT CASE WHEN ls.id_house IS NOT NULL THEN f.sk_house_listing_flow ELSE NULL END) AS hybrid_listings,
        SUM(0::FLOAT) AS cost,
        SUM(0::FLOAT) AS prospects_target,
        SUM(0::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(0::FLOAT) AS budget
    FROM
        fact_house_listing_flows f
        JOIN dim_lead dl
            ON dl.sk_lead = f.sk_lead
        JOIN dim_region dr
            ON f.sk_region = dr.sk_region
        JOIN dim_date AS dd
            ON f.sk_first_listing_date = dd.sk_date
        LEFT JOIN listings_sale AS ls
            ON SUBSTRING(f.sk_house_listing, 1, 9) = ls.id_house
            AND dd.month_start = ls.month_start
        LEFT JOIN datalake_wololo_clean_prod.prospect p
            ON p.id_reference = f.sk_lead
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12

  UNION ALL

  -----------------------------------------
  -- Supply ForRental Marketing Investment --
  -----------------------------------------
 (
WITH
affiliates AS (
    WITH
    ia_fact_cost AS (
        SELECT
            fc.sk_date,
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
            marketing.fact_marketing_daily_costs fc
        WHERE
            fc.mkt_origin = 'Indica Aí - General'
    ),
    ia_affiliate_commission_costs AS (
        WITH commission_costs AS (
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
                cc.sk_date,
                cc.mkt_origin,
                NULL::TEXT AS mkt_channel,
                NULL::TEXT AS mkt_medium,
                NULL::TEXT AS mkt_source,
                NULL::TEXT AS utm_campaign,
                NULL::TEXT AS utm_content,
                NULL::TEXT AS utm_term,
                cc.city_group,
                cc.source,
                CASE
                    WHEN cc.cost_center_code = 'C046' THEN 'Sale'
                    ELSE 'Rent'
                END AS business_context,
                SUM(cc.cost) AS cost
            FROM
                commission_costs cc
            WHERE cc.sk_date >= 20210125
            GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    ),
    promo_bonus AS (
        SELECT
            sk_date,
            CASE
                WHEN affiliate_type = 'Standard' THEN 'Indica Aí - General'
                WHEN affiliate_type = 'Agent' THEN 'Indica Aí - Agents'
                WHEN affiliate_type = 'Doorman' THEN 'Doorman'
                ELSE affiliate_type
            END AS mkt_origin,
            NULL::TEXT AS mkt_channel,
            NULL::TEXT AS mkt_medium,
            NULL::TEXT AS mkt_source,
            NULL::TEXT AS utm_campaign,
            NULL::TEXT AS utm_content,
            NULL::TEXT AS utm_term,
            city_group,
            'Promo Bonus' AS source,
            'Rent' AS business_context,
            SUM(final_bonus_rent) AS cost
        FROM
            datamarts.performance_marketing_promotional_bonus_costs_daily
        WHERE final_bonus_rent > 0
        AND sk_date >= 20210208
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
            NULL::TEXT AS mkt_channel,
            NULL::TEXT AS mkt_medium,
            NULL::TEXT AS mkt_source,
            NULL::TEXT AS utm_campaign,
            NULL::TEXT AS utm_content,
            NULL::TEXT AS utm_term,
            city_group,
            'Promo Bonus' AS source,
            'Sale' AS business_context,
            SUM(final_bonus_sale) AS cost
        FROM
            datamarts.performance_marketing_promotional_bonus_costs_daily
        WHERE final_bonus_sale > 0
        AND sk_date >= 20210208
        GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    ),
    ia_fact_affiliate_transposed AS (
        SELECT sk_date, mkt_origin, NULL::TEXT AS mkt_channel, NULL::TEXT AS mkt_medium, NULL::TEXT AS mkt_source, NULL::TEXT AS utm_campaign, NULL::TEXT AS utm_content, NULL::TEXT AS utm_term, city_group, 'Commission Listing' AS source, NULL AS business_context, commission_listing AS cost FROM marketing.fact_affiliate_daily_cost_attributions WHERE sk_date < 20210125
        UNION ALL
        SELECT sk_date,	mkt_origin, NULL::TEXT AS mkt_channel, NULL::TEXT AS mkt_medium, NULL::TEXT AS mkt_source, NULL::TEXT AS utm_campaign, NULL::TEXT AS utm_content, NULL::TEXT AS utm_term, city_group, 'Commission Rent' AS source, NULL AS business_context, commission_rent AS cost FROM	marketing.fact_affiliate_daily_cost_attributions WHERE sk_date < 20210125
        UNION ALL
        SELECT sk_date, mkt_origin, NULL::TEXT AS mkt_channel, NULL::TEXT AS mkt_medium, NULL::TEXT AS mkt_source, NULL::TEXT AS utm_campaign, NULL::TEXT AS utm_content, NULL::TEXT AS utm_term, city_group, 'Commission MGM' AS source, NULL AS business_context, commission_mgm AS cost FROM marketing.fact_affiliate_daily_cost_attributions WHERE sk_date < 20210125
        UNION ALL
        SELECT sk_date, mkt_origin, NULL::TEXT AS mkt_channel, NULL::TEXT AS mkt_medium, NULL::TEXT AS mkt_source, NULL::TEXT AS utm_campaign, NULL::TEXT AS utm_content, NULL::TEXT AS utm_term, city_group, 'Commission Tradecom' AS source, NULL AS business_context, commission_tradecom AS cost FROM marketing.fact_affiliate_daily_cost_attributions
        UNION ALL
        SELECT sk_date, mkt_origin, NULL::TEXT AS mkt_channel, NULL::TEXT AS mkt_medium, NULL::TEXT AS mkt_source, NULL::TEXT AS utm_campaign, NULL::TEXT AS utm_content, NULL::TEXT AS utm_term, city_group, 'Promo Bonus' AS source, NULL AS business_context, promotional_bonus AS cost FROM marketing.fact_affiliate_daily_cost_attributions  WHERE sk_date < 20210208
        UNION ALL
        SELECT sk_date,	mkt_origin, NULL::TEXT AS mkt_channel, NULL::TEXT AS mkt_medium, NULL::TEXT AS mkt_source, NULL::TEXT AS utm_campaign, NULL::TEXT AS utm_content, NULL::TEXT AS utm_term, city_group, 'Notification' AS source, NULL AS business_context, notification AS cost FROM marketing.fact_affiliate_daily_cost_attributions
        UNION ALL
        SELECT sk_date, mkt_origin, NULL::TEXT AS mkt_channel, NULL::TEXT AS mkt_medium, NULL::TEXT AS mkt_source, NULL::TEXT AS utm_campaign, NULL::TEXT AS utm_content, NULL::TEXT AS utm_term, city_group, 'Other' AS source, NULL AS business_context, other AS cost FROM marketing.fact_affiliate_daily_cost_attributions
    ),
    ia_provisioned_costs AS (
        SELECT
            TO_CHAR(NULLIF(DATE,'')::DATE,'yyyymmdd')::BIGINT AS sk_date,
            NULLIF(cost_origin,'')::VARCHAR AS mkt_origin,
            NULL::TEXT AS mkt_channel,
            NULL::TEXT AS mkt_medium,
            NULL::TEXT AS mkt_source,
            NULL::TEXT AS utm_campaign,
            NULL::TEXT AS utm_content,
            NULL::TEXT AS utm_term,
            NULLIF(city_group,'')::VARCHAR AS city_group,
            NULLIF(cost_type,'')::VARCHAR AS source,
            NULL AS business_context,
            NULLIF(cost,'')::float AS cost
        FROM
            datalake_raw.gsheets_provisioned_costs_import
    ),
    ia_total_cost AS (
        SELECT	* FROM ia_fact_cost
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
    JOIN dim_date dd
        ON dd.sk_date = iac.sk_date
    WHERE
        iac.cost IS NOT NULL
        AND dd.date < CURRENT_DATE
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    HAVING costs>0
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
    FROM base
    GROUP BY 1,2,3,4,5,6,7,8,9,10
    ),
    affiliates_sale_cost AS (
    SELECT
        sk_date,
        city_group,
        replace(mkt_origin,' Sale','') AS mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        utm_campaign,
        utm_content,
        utm_term,
        NULL::TEXT AS origin_phone,
        NULL::TEXT AS campaign_context,
        'Sale' as business,
        COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(costs)::FLOAT AS cost,
        SUM(0::FLOAT) AS prospects_target,
        SUM(0::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(0::FLOAT) AS budget
    FROM affiliates
    WHERE business_context = 'Sale' OR (business_context is NULL AND mkt_origin IN ('Doorman Sale','Indica Aí - Agents Sale','Indica Aí - General Sale'))
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
    ),
    supply_affiliates_cost AS (
    SELECT
        sk_date,
        city_group,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        utm_campaign,
        utm_content,
        utm_term,
        NULL::TEXT AS origin_phone,
        NULL::TEXT AS campaign_context,
        'Rental' as business,
        COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(costs)::FLOAT AS cost,
        SUM(0::FLOAT) AS prospects_target,
        SUM(0::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(0::FLOAT) AS budget
    FROM affiliates
    WHERE business_context = 'Rent' OR (business_context is NULL AND mkt_origin IN ('Doorman','Indica Aí - Agents','Indica Aí - General'))
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
    ),
    supply_landlords_cost AS (
    SELECT
        dbt.sk_date AS sk_date,
        co.city_group,
        CASE WHEN co.mkt_origin = 'Owner PWA' THEN 'PWA - '||co.mkt_channel ELSE co.mkt_origin END AS mkt_origin,
        co.mkt_channel AS mkt_channel,
        co.mkt_medium AS mkt_medium,
        co.mkt_source AS mkt_source,
        co.utm_campaign AS utm_campaign,
        co.utm_content AS utm_content,
        co.utm_term AS utm_term,
        NULL::TEXT AS origin_phone,
        NULL::TEXT AS campaign_context,
        'Rental' AS business,
        COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(co.cost)::FLOAT AS cost,
        SUM(0::FLOAT) AS prospects_target,
        SUM(0::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(0::FLOAT) AS budget
    FROM marketing.fact_marketing_daily_costs co
    JOIN dim_date dbt on dbt.sk_date = co.sk_date
    WHERE co.funnel_side = 'supply'
      AND dbt.date BETWEEN '2020-01-01' AND (CURRENT_DATE - interval '1 day')
      AND co.mkt_origin IN ('Owner PWA','Price Calculator','New Channels')
      AND co.mkt_channel != 'Girafa'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
    ),
    supply_sale_cost AS (
    SELECT
        dbt.sk_date AS sk_date,
        co.city_group AS city_group,
        co.mkt_origin AS mkt_origin,
        co.mkt_channel AS mkt_channel,
        co.mkt_medium AS mkt_medium,
        co.mkt_source AS mkt_source,
        co.utm_campaign AS utm_campaign,
        co.utm_content AS utm_content,
        co.utm_term AS utm_term,
        NULL::TEXT AS origin_phone,
        NULL::TEXT AS campaign_context,
        'Sale' AS business,
        COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(co.cost)::FLOAT AS cost,
        SUM(0::FLOAT) AS prospects_target,
        SUM(0::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(0::FLOAT) AS budget
    FROM marketing.fact_marketing_daily_costs co
    JOIN dim_date dbt ON dbt.sk_date = co.sk_date
    WHERE co.account_name IN ('quintoandar_supply_sale_display', 'quintoandar_supply_sale', 'supply_landlords_sale', 'supply_landlords')
      AND co.mkt_origin IN ('Owner PWA - Sale', 'Price Calculator - Sale')
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
    ),
    supply_ciq_cost AS (
    SELECT
        dbt.sk_date AS sk_date,
        co.city_group AS city_group,
        co.mkt_origin AS mkt_origin,
        co.mkt_channel AS mkt_channel,
        co.mkt_medium AS mkt_medium,
        co.mkt_source AS mkt_source,
        co.utm_campaign AS utm_campaign,
        co.utm_content AS utm_content,
        co.utm_term AS utm_term,
        NULL::TEXT AS origin_phone,
        NULL::TEXT AS campaign_context,
        'Rental' AS business,
        COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(co.cost)::FLOAT AS cost,
        SUM(0::FLOAT) AS prospects_target,
        SUM(0::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(0::FLOAT) AS budget
    FROM marketing.fact_marketing_daily_costs co
    JOIN dim_date dbt ON dbt.sk_date = co.sk_date
    WHERE co.mkt_origin = 'CIQ'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
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
    SELECT * FROM cost_union
    WHERE sk_date < TO_CHAR(current_date,'yyyymmdd')::bigint
    AND business = 'Rental'
    AND cost > 0
    AND cost IS NOT NULL
)

  UNION ALL

  -------------------------------------------
  -- Supply ForRental Funnel Targets - NEW --
  -------------------------------------------
    SELECT
        TO_CHAR(DATE(NULLIF(str.date, NULL)), 'YYYYMMDD')::INT AS sk_date,
        COALESCE(NULLIF(str.city_group, ''),'Not Mapped')::TEXT AS city_group,
        str.supply_origin AS mkt_origin,
        str.supply_channel AS mkt_channel,
        str.supply_medium AS mkt_medium,
        str.supply_source AS mkt_source,
        NULL::TEXT AS utm_campaign,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS origin_phone,
        'Rental' campaign_context,
        'Rental' AS business_context,
        COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(0::FLOAT) AS cost,
        SUM(NULLIF(str.prospects, '')::FLOAT) AS prospects_target,
        SUM(NULLIF(str.qualifieds, '')::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(NULLIF(str.cost_per_source, '')::FLOAT) AS budget
    FROM
        datalake_raw.gsheets_daily_target_supply_rental str
    WHERE str.date >= '2021-04-01'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12

  UNION ALL

  -------------------------------------------
  -- Supply ForRental Funnel Targets - OLD --
  -------------------------------------------
    SELECT
        TO_CHAR(DATE(NULLIF(str.date, NULL)), 'YYYYMMDD')::INT AS sk_date,
        COALESCE(NULLIF(str.city_group,''),'Not Mapped')::varchar AS city_group,
        NULLIF(str.supply_origin,'')::varchar AS mkt_origin,
        NULLIF(str.supply_channel,'')::varchar AS mkt_channel,
        NULL::TEXT AS mkt_medium,
        NULL::TEXT AS mkt_source,
        NULL::TEXT AS utm_campaign,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS origin_phone,
        NULL::TEXT AS campaign_context,
        'Rental' AS business_context,
        COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(0::FLOAT) AS cost,
        SUM(NULLIF(str.prospect,'')::float) AS prospects_target,
        SUM(NULLIF(str.qualified,'')::float) AS qualifieds_target,
        SUM(NULLIF(str.opportunity,'')::float) AS opportunities_target,
        SUM(NULLIF(str.first_listing,'')::float) AS first_listings_target,
        SUM(0::FLOAT) AS budget
    FROM
        datamarts.daily_target_volumes_supply str
    WHERE str.date < '2021-04-01'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12

  UNION ALL
  -----------------------------------------
  -- Supply ForRental Cost Targets - OLD --
  -----------------------------------------
    SELECT
        TO_CHAR(DATE(NULLIF(sct.date, NULL)), 'YYYYMMDD')::INT AS sk_date,
        COALESCE(nullif(sct.city_group,''),'Not Mapped')::varchar AS city_group,
        CASE
            WHEN sct.planning_mkt_level3 = 'PWA - Paid'
                THEN 'Owner PWA'
            ELSE sct.planning_mkt_level3
        END AS mkt_origin,
        CASE
            WHEN planning_mkt_level3  = 'PWA - Paid' THEN 'Paid'
            WHEN planning_mkt_level3 = 'Not Mapped' THEN 'Other'
            WHEN planning_mkt_level3 IN ('Autonomous Agent', 'Autonomuos Agent') THEN 'CIQ'
        ELSE planning_mkt_level3 END AS mkt_channel,
        NULL::TEXT AS mkt_medium,
        NULL::TEXT AS mkt_source,
        NULL::TEXT AS utm_campaign,
        NULL::TEXT AS utm_content,
        NULL::TEXT AS utm_term,
        NULL::TEXT AS origin_phone,
        campaign AS campaign_context,
        business AS business_context,
        COUNT(NULL) AS leads,
        COUNT(NULL) AS prospects,
        COUNT(NULL) AS qualifieds,
        COUNT(NULL) AS opportunities,
        COUNT(NULL) AS first_listings,
        COUNT(NULL) AS hybrid_listings,
        SUM(0::FLOAT) AS cost,
        SUM(0::FLOAT) AS prospects_target,
        SUM(0::FLOAT) AS qualifieds_target,
        SUM(0::FLOAT) AS opportunities_target,
        SUM(0::FLOAT) AS first_listings_target,
        SUM(nullif((replace(sct.budget__mensal,',','')),'')::float) AS budget
    FROM
        datalake_raw.gsheets_costs_targets sct
    WHERE planning_mkt_level1 = 'Supply'
        AND sct.date < '2021-04-01'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
)
SELECT
    date,
    city_group,
    CASE
        WHEN mkt_origin = 'PWA - Paid' THEN 'Owner PWA'
        WHEN mkt_origin LIKE '% - Sale' THEN replace(mkt_origin,' - Sale','')
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
        WHEN mkt_origin = 'Price Calculator - Sale' THEN 'Price Calculator'
        WHEN mkt_origin IN ('CR', 'Autonomous Agent', 'Autonomuos Agent') THEN 'CIQ'
        ELSE mkt_origin
    END AS planning_mkt_channel,
    mkt_medium,
    mkt_source,
    utm_campaign,
    utm_content,
    utm_term,
    NULLIF(origin_phone,'') AS origin_phone,
    CASE
        WHEN campaign_context = 'Rent' THEN 'Rental'
        ELSE campaign_context
    END AS campaign_context,
    CASE
        WHEN business_context = 'Rent' THEN 'Rental'
        ELSE business_context
    END AS business_context,
    SUM(leads) AS leads,
    SUM(prospects) AS prospects,
    SUM(qualifieds) AS qualifieds,
    SUM(opportunities) AS opportunities,
    SUM(first_listings) AS first_listings,
    SUM(hybrid_listings) AS hybrid_listings,
    SUM(cost) AS cost,
    SUM(prospects_target) AS prospects_target,
    SUM(qualifieds_target) AS qualifieds_target,
    SUM(opportunities_target) AS opportunities_target,
    SUM(first_listings_target) AS first_listings_target,
    SUM(budget) AS budget
FROM costs_targets_results_combined
  JOIN dim_date AS dd
    USING(sk_date)
WHERE business_context = 'Rental'
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13
