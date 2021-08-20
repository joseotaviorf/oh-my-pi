WITH
ia_fact_cost AS (
	SELECT
		fc.sk_date,
		'fact_cost' AS table,
		mkt_origin,
		fc.city_group,
		CASE
			WHEN fc.utm_campaign ILIKE '%acq%' THEN 'acquisition'
			WHEN fc.utm_campaign ILIKE '%eng%' THEN 'engagement'
			WHEN fc.mkt_source = 'Bing' THEN 'acquisition'
			ELSE NULL
		END AS vertical,
		CASE
			WHEN fc.mkt_source IN ('Twilio', 'Movile') THEN 'Notification'
			ELSE mkt_source
		END AS source,
		NULL as business_context,
		fc.cost
	FROM
		marketing.fact_marketing_daily_costs fc
	WHERE fc.mkt_origin = 'Indica Aí - General'
	AND fc.mkt_source <> 'Spinver'
),
ia_affiliate_commission_costs AS (
    WITH commission_costs AS
        (SELECT
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
        WHERE sk_user NOT IN (360754,912255,1711931,2257503)
        )
        SELECT
            cc.sk_date,
            'rh_datamart' AS table,
        	cc.mkt_origin,
        	cc.city_group,
        	CASE
        	    WHEN cc.source = 'Commission MGM' THEN 'acquisition'
        	    ELSE 'engagement'
        	END AS vertical,
        	cc.source,
        	CASE
        	    WHEN cc.cost_center_code = 'C046' THEN 'sale'
        	    ELSE 'rent'
        	END AS business_context,
        	SUM(cc.cost) AS cost
        FROM
            commission_costs cc
        WHERE cc.sk_date >= 20210125
        AND mkt_origin <> 'Doorman'
        GROUP BY 1,2,3,4,5,6,7
),
promo_bonus AS (
WITH segmentation_promo_bonus AS(
    SELECT
        sk_date,
        'pb_datamart' AS table,
        CASE
            WHEN affiliate_type = 'Standard' THEN 'Indica Aí - General'
            WHEN affiliate_type = 'Agent' THEN 'Indica Aí - Agents'
            WHEN affiliate_type = 'Doorman' THEN 'Doorman'
            ELSE affiliate_type
        END AS mkt_origin,
        city_group,
        'engagement' AS vertical,
        'Promotional Bonus' AS source,
        'rent' AS business_context,
        SUM(final_bonus_rent) AS cost
    FROM
        datamarts.performance_marketing_promotional_bonus_costs_daily
    WHERE final_bonus_rent > 0
    AND sk_date >= 20210208
    AND sk_date < 20210701
    GROUP BY 1,2,3,4,5,6,7

    UNION ALL

    SELECT
        sk_date,
        'pb_datamart' AS table,
        CASE
            WHEN affiliate_type = 'Standard' THEN 'Indica Aí - General'
            WHEN affiliate_type = 'Agent' THEN 'Indica Aí - Agents'
            WHEN affiliate_type = 'Doorman' THEN 'Doorman'
            ELSE affiliate_type
        END AS mkt_origin,
        city_group,
        'engagement' AS vertical,
        'Promotional Bonus' AS source,
        'sale' AS business_context,
        SUM(final_bonus_sale) AS cost
    FROM
        datamarts.performance_marketing_promotional_bonus_costs_daily
    WHERE final_bonus_sale > 0
    AND sk_date >= 20210208
    AND sk_date < 20210701
    GROUP BY 1,2,3,4,5,6,7
),
cluster_promo_bonus AS(
    SELECT
        sk_date,
        'pb_datamart' AS table,
        CASE
            WHEN affiliate_type = 'Standard' THEN 'Indica Aí - General'
            WHEN affiliate_type = 'Agent' THEN 'Indica Aí - Agents'
            WHEN affiliate_type = 'Doorman' THEN 'Doorman'
            ELSE affiliate_type
        END AS mkt_origin,
        city_group,
        'engagement' AS vertical,
        'Promotional Bonus' AS source,
        'rent' AS business_context,
        SUM(final_bonus_rent) AS cost
    FROM
        datamarts.performance_marketing_cluster_promotional_bonus_costs
    WHERE final_bonus_rent > 0
    AND sk_date >= 20210701
    GROUP BY 1,2,3,4,5,6,7

    UNION ALL

    SELECT
        sk_date,
        'pb_datamart' AS table,
        CASE
            WHEN affiliate_type = 'Standard' THEN 'Indica Aí - General'
            WHEN affiliate_type = 'Agent' THEN 'Indica Aí - Agents'
            WHEN affiliate_type = 'Doorman' THEN 'Doorman'
            ELSE affiliate_type
        END AS mkt_origin,
        city_group,
        'engagement' AS vertical,
        'Promotional Bonus' AS source,
        'sale' AS business_context,
        SUM(final_bonus_sale) AS cost
    FROM
        datamarts.performance_marketing_cluster_promotional_bonus_costs
    WHERE final_bonus_sale > 0
    AND sk_date >= 20210701
    GROUP BY 1,2,3,4,5,6,7
)
SELECT * FROM segmentation_promo_bonus
UNION ALL
SELECT * FROM cluster_promo_bonus
),
ia_fact_affiliate_transposed AS (
    SELECT
        sk_date,
        'fact_affiliate' AS table,
        mkt_origin,
        city_group,
        'engagement' AS vertical,
         'Commission Listing' AS source,
         NULL AS business_context,
         commission_listing AS cost
    FROM marketing.fact_affiliate_daily_cost_attributions
    WHERE sk_date < 20210125
	UNION ALL
	SELECT
	    sk_date,
	    'fact_affiliate' AS table,
	    mkt_origin,
	    city_group,
	    'engagement' AS vertical,
	    'Commission Rent' AS source,
	    NULL AS business_context,
	    commission_rent AS cost
    FROM marketing.fact_affiliate_daily_cost_attributions
    WHERE sk_date < 20210125
	UNION ALL
	SELECT
	    sk_date,
	    'fact_affiliate' AS table,
	    mkt_origin,
	    city_group,
	    'acquisition' AS vertical,
	    'Commission MGM' AS source,
	    NULL AS business_context,
	    commission_mgm AS cost
    FROM marketing.fact_affiliate_daily_cost_attributions
    WHERE sk_date < 20210125
	UNION ALL
	SELECT
	    sk_date,
	    'fact_affiliate' AS table,
	    mkt_origin,
	    city_group,
	    'engagement' AS vertical,
	    'Commission Tradecom' AS source,
	    NULL AS business_context,
	    commission_tradecom AS cost
    FROM marketing.fact_affiliate_daily_cost_attributions
	UNION ALL
	SELECT
	    sk_date,
	    'fact_affiliate' AS table,
	    mkt_origin,
	    city_group,
	    'engagement' AS vertical,
	    'Promotional Bonus' AS source,
	    NULL AS business_context,
	    promotional_bonus AS cost
    FROM marketing.fact_affiliate_daily_cost_attributions
    WHERE sk_date < 20210208
	UNION ALL
	SELECT
	    sk_date,
	    'fact_affiliate' AS table,
	    mkt_origin,
	    city_group,
	    'engagement' AS vertical,
	    'Notification' AS source,
	    NULL AS business_context,
	    notification AS cost
    FROM marketing.fact_affiliate_daily_cost_attributions
	UNION ALL
	SELECT
	    sk_date,
	    'fact_affiliate' AS table,
	    mkt_origin,
	    city_group,
	    'engagement' AS vertical,
	    'Other' AS source,
	    NULL AS business_context,
	    other AS cost
    FROM marketing.fact_affiliate_daily_cost_attributions
),
ia_provisioned_costs AS (
	SELECT
		TO_CHAR(NULLIF(date,'')::date,'yyyymmdd')::bigint AS sk_date,
		'sheets' AS table,
		NULLIF(cost_origin,'')::varchar AS mkt_origin,
		NULLIF(city_group,'')::varchar AS city_group,
		NULL::text AS vertical,
		NULLIF(cost_type,'')::varchar AS source,
		NULL AS business_context,
		NULLIF(cost,'')::float AS cost
	FROM datalake_raw.gsheets_provisioned_costs_import
),
ia_sale_costs AS (
    WITH lbc_rent AS (
        SELECT
            DISTINCT
            CAST(id_house AS bigint) AS id_house,
            CAST(ts_first_publication AS date) AS dt_first_publication
        FROM datalake_ebdb_clean_prod.listing_business_context lbc
        WHERE business_context ='RENT'
        AND ts_first_publication IS NOT NULL
    ),
    listings_sale AS(
        SELECT
            sk_first_listing_date AS sk_first_listing_date,
            lf.sk_user_lead_affiliate AS id_user,
            lf.sk_house_listing/1000 AS id_house,
            CASE
                WHEN lf.listing_rent_status = 'Once Published' THEN true
                ELSE false
            END AS listing_rent,
            dr.city_group,
            lf.mkt_origin,
            lf.affiliate_type,
            CASE WHEN date_trunc('month', rbc.dt_first_publication) = date_trunc('month', dd.date)
                THEN true
                ELSE false
            END AS flag_publication_sale_and_rent_same_month
        FROM sale.fact_listing_flows lf
        LEFT JOIN dim_date dd
            ON dd.sk_date = lf.sk_first_listing_date
        LEFT JOIN dim_region dr
            ON dr.sk_region = lf.sk_region
        LEFT JOIN datalake_ebdb_clean_prod.listing_business_context lbc
            ON lbc.id_house = lf.sk_house_listing/1000
            AND lbc.business_context = 'SALE'
        LEFT JOIN lbc_rent rbc
            ON rbc.id_house = lf.sk_house_listing/1000
        WHERE lf.sk_first_listing_date > 0
        AND lf.sk_user_lead_affiliate > 0
        AND lf.mkt_origin IN ('Doorman', 'Indica Aí - Agents', 'Indica Aí - General')
        AND lf.sk_user_lead_affiliate NOT IN (360754,912255,1711931,2257503)
    )
    (SELECT
        sk_first_listing_date,
        'sale_flows' AS table,
        mkt_origin,
        city_group,
        'engagement' AS vertical,
        'Comission Listing' AS source,
        CASE
            WHEN flag_publication_sale_and_rent_same_month = 'false' THEN 'sale'
            ELSE 'hybrid'
        END AS business_context,
        CASE
            WHEN flag_publication_sale_and_rent_same_month = 'false' THEN (COUNT(id_house))*100
            ELSE (COUNT(id_house))*50
        END AS cost
    FROM
        listings_sale
    WHERE mkt_origin = 'Doorman'
    AND sk_first_listing_date >= 20210125
    GROUP BY 1,2,3,4,5,6,7, flag_publication_sale_and_rent_same_month
    )

    UNION ALL

    (SELECT
        sk_first_listing_date,
        'sale_flows' AS table,
        mkt_origin,
        city_group,
        'engagement' AS vertical,
        'Comission Listing' AS source,
        CASE
            WHEN flag_publication_sale_and_rent_same_month = 'false' THEN 'sale'
            ELSE 'hybrid'
        END AS business_context,
        CASE
            WHEN flag_publication_sale_and_rent_same_month = 'false' THEN (COUNT(id_house))*100
            ELSE (COUNT(id_house))*50
        END AS cost
    FROM
        listings_sale
    WHERE mkt_origin <> 'Doorman'
    AND sk_first_listing_date < 20210125
    GROUP BY 1,2,3,4,5,6,7, flag_publication_sale_and_rent_same_month
    )
),

doorman_rent_costs AS (
    WITH lbc_sale AS (
        SELECT
            DISTINCT
            CAST(id_house AS bigint) AS id_house,
            CAST(ts_first_publication AS date) AS dt_first_publication
        FROM
            datalake_ebdb_clean_prod.listing_business_context lbc
        WHERE business_context ='SALE'
        AND ts_first_publication IS NOT NULL
    ),
    listings_sale AS(
        SELECT
            sk_first_listing_date AS sk_first_listing_date,
            lf.sk_user_lead_affiliate AS id_user,
            lf.sk_house_listing/1000 AS id_house,
            dr.city_group,
            lf.mkt_origin,
            lf.affiliate_type,
            CASE WHEN date_trunc('month', sbc.dt_first_publication) = date_trunc('month', dd.date)
                THEN true
                ELSE false
            END AS flag_publication_sale_and_rent_same_month
        FROM
            fact_house_listing_flows lf
        LEFT JOIN dim_date dd
            ON dd.sk_date = lf.sk_first_listing_date
        LEFT JOIN dim_region dr
            ON dr.sk_region = lf.sk_region
        LEFT JOIN datalake_ebdb_clean_prod.listing_business_context lbc
            ON lbc.id_house = lf.sk_house_listing/1000
            AND lbc.business_context = 'RENT'
        LEFT JOIN lbc_sale sbc
            ON sbc.id_house = lf.sk_house_listing/1000
        WHERE lf.sk_first_listing_date > 0
        AND lf.sk_user_lead_affiliate > 0
        AND lf.mkt_origin = 'Doorman'
        AND lf.sk_user_lead_affiliate NOT IN (360754,912255,1711931,2257503)
    )
        SELECT
            sk_first_listing_date,
            'rent_flows' AS table,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Comission Listing' AS source,
            CASE
                WHEN flag_publication_sale_and_rent_same_month = 'false' THEN 'rent'
                ELSE 'hybrid'
            END AS business_context,
            CASE
                WHEN flag_publication_sale_and_rent_same_month = 'false' THEN (COUNT(id_house))*100
                ELSE (COUNT(id_house))*50
            END AS cost
        FROM
            listings_sale
        WHERE sk_first_listing_date >= 20210125
        GROUP BY 1,2,3,4,5,6,7, flag_publication_sale_and_rent_same_month
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
	UNION ALL
	SELECT * FROM ia_sale_costs
	UNION ALL
	SELECT * FROM doorman_rent_costs
)
SELECT
	TO_CHAR(dd.date, 'yyyy-mm-dd') date,
	TO_CHAR(dd.week_start, 'yyyy-mm-dd') week_start,
	dd.year_month,
	iac.table,
	iac.mkt_origin,
	iac.city_group,
	iac.vertical,
	iac.source,
	iac.business_context,
	SUM(iac.cost) AS costs,
	date_part("month",dd.date) month_num
FROM
	ia_total_cost iac
JOIN dim_date dd
	ON dd.sk_date = iac.sk_date
WHERE iac.cost IS NOT NULL
AND dd.date < CURRENT_DATE
GROUP BY 1,2,3,4,5,6,7,8,9,11
HAVING costs>0
ORDER BY 1 DESC,2,3,4,5,6,7,8,10