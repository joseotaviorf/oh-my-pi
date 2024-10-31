WITH
demand_cost AS (
    SELECT
        dbt.date AS dt_cost,
        co.city_group AS city_group,
        'Rental' AS business,
        'Demand' AS planning_mkt_level1,
        CASE
            WHEN co.mkt_channel LIKE '%Paid%' OR co.mkt_channel = 'Performance Max'
                THEN 'Paid'
            ELSE co.mkt_channel
            END AS planning_mkt_level2,
        co.mkt_medium AS planning_mkt_level3,
        SUM(co.cost) AS costs
    FROM
        datalake_marketing_costs.daily_costs AS co
    JOIN dw_public.dim_date AS dbt
        ON dbt.sk_date = co.id_date
    WHERE
        co.funnel_side = 'demand'
        AND dbt.date BETWEEN DATE('2019-01-01') AND CURRENT_DATE - INTERVAL "1" day
        AND co.mkt_medium != 'Branding'
        AND co.mkt_channel != 'Paid Traffic'
        AND co.mkt_origin = 'Tenants PWA'
    GROUP BY 1, 2, 3, 4, 5, 6
),
affiliates AS (
   WITH
    ia_fact_cost AS (
        (SELECT
            fc.id_date as sk_date,
            'fact_cost' AS table_origin,
            fc.mkt_origin,
            fc.city_group,
            CASE
                WHEN (LOWER(fc.utm_campaign) LIKE '%acq%')  OR (fc.campaign_name LIKE '%acq%') THEN 'acquisition'
                WHEN (LOWER(fc.utm_campaign) LIKE '%eng%') OR (fc.campaign_name LIKE '%eng%') THEN 'engagement'
                WHEN fc.mkt_source = 'Bing' THEN 'acquisition'
                ELSE NULL
            END AS vertical,
            CASE
                WHEN fc.mkt_source IN ('Twilio', 'Movile')
                    THEN 'Notification'
                ELSE mkt_source
            END AS source, 
            CASE
			    WHEN (LOWER(fc.utm_campaign) LIKE '%sale%')  OR (LOWER(fc.campaign_name) LIKE '%sale%') THEN 'sale'
			    WHEN (LOWER(fc.utm_campaign) LIKE '%rent%') OR (LOWER(fc.campaign_name) LIKE '%rent%') THEN 'rent'
			    ELSE NULL
		    END AS business_context,
            fc.cost
        FROM
            datalake_marketing_costs.daily_costs AS fc
        WHERE
            fc.mkt_origin in ('Indica Aí - General', 'Indica Aí - Agents', 'Doorman') 
            AND fc.flow_type != 'historical'
            AND fc.id_date BETWEEN 20210101 AND 20210701
            OR (fc.mkt_origin IN ('Indica Aí - General', 'Indica Aí - Agents', 'Doorman')
                AND flow_type != 'historical'
                AND fc.id_date >= 20210701
                AND fc.mkt_source != 'Spinver')
        )
        UNION ALL
        (SELECT
            fc.id_date as sk_date,
            'fact_cost' AS table_origin,
            fc.mkt_origin,
            fc.city_group,
            CASE
                WHEN (LOWER(fc.utm_campaign) LIKE '%acq%')  OR (fc.campaign_name LIKE '%acq%') THEN 'acquisition'
                WHEN (LOWER(fc.utm_campaign) LIKE '%eng%') OR (fc.campaign_name LIKE '%eng%') THEN 'engagement'
                WHEN fc.mkt_source = 'Bing' THEN 'acquisition'
                ELSE NULL
            END AS vertical,
            CASE
                WHEN fc.mkt_source IN ('Twilio', 'Movile')
                    THEN 'Notification'
                ELSE mkt_source
            END AS source,
            CASE
			    WHEN (LOWER(fc.utm_campaign) LIKE '%sale%')  OR (LOWER(fc.campaign_name) LIKE '%sale%') THEN 'sale'
			    WHEN (LOWER(fc.utm_campaign) LIKE '%rent%') OR (LOWER(fc.campaign_name) LIKE '%rent%') THEN 'rent'
			    ELSE NULL
		    END AS business_context,
            fc.cost
        FROM
            datalake_marketing_costs.daily_costs fc
        WHERE fc.mkt_origin = 'Indica Aí - General'
        AND fc.id_date < 20210101
        )
    ),
    ia_affiliate_commission_costs AS (
        WITH
        commission_costs AS (
            SELECT 
                DISTINCT f.sk_rh_accounting_entry,
                d.mkt_origin,
                d.city_group,
                f.sk_date,
                d.commission_type AS source,
                d.cost_center_code,
                f.cost
            FROM 
                dw_quintoandar.fact_affiliate_costs AS f
            LEFT JOIN dw_quintoandar.dim_affiliate_cost AS d
                ON f.sk_rh_accounting_entry = d.sk_rh_accounting_entry
            WHERE f.sk_date < 20210701
                OR (f.sk_date >= 20210701
                    AND sk_user NOT IN (360754,912255,1711931,2257503))
        )
        SELECT 
            cc.sk_date,
            'rh_datamart' AS table_origin,
            cc.mkt_origin,
            cc.city_group,
            CASE
                WHEN cc.source = 'Commission MGM'
                    THEN 'acquisition' 
                ELSE 'engagement'
            END AS vertical,
            cc.source,
            CASE 
                WHEN cc.cost_center_code IN ('C046', 'S01305', 'S02305')
                    THEN 'sale'
                ELSE 'rent'
            END AS business_context,
            SUM(cc.cost) AS cost
        FROM 
            commission_costs AS cc
        WHERE
            cc.sk_date >= 20210125
            AND mkt_origin <> 'Doorman'
        GROUP BY 1,2,3,4,5,6,7
    ),
    promo_bonus AS (
        WITH 
        segmentation_promo_bonus AS (
            SELECT 
                sk_date,
                'pb_datamart' AS table_origin,
                CASE 
                    WHEN affiliate_type = 'Standard'
                        THEN 'Indica Aí - General'
                    WHEN affiliate_type = 'Agent'
                        THEN 'Indica Aí - Agents'
                    ELSE affiliate_type
                END AS mkt_origin,
                city_group,
                'engagement' AS vertical,
                'Promotional Bonus' AS source,
                'rent' AS business_context,
                SUM(final_bonus_rent) AS cost
            FROM 
                dw_datamarts.performance_marketing_promotional_bonus_costs_daily
            WHERE final_bonus_rent > 0
                AND sk_date BETWEEN 20210208 AND 20210630
            GROUP BY 1,2,3,4,5,6,7
            
            UNION ALL
            
            SELECT 
                sk_date,
                'pb_datamart' AS table_origin,
                CASE 
                    WHEN affiliate_type = 'Standard'
                        THEN 'Indica Aí - General'
                    WHEN affiliate_type = 'Agent'
                        THEN 'Indica Aí - Agents'
                    ELSE affiliate_type
                END AS mkt_origin,
                city_group,
                'engagement' AS vertical,
                'Promotional Bonus' AS source,
                'sale' AS business_context,
                SUM(final_bonus_sale) AS cost
            FROM 
                dw_datamarts.performance_marketing_promotional_bonus_costs_daily
            WHERE final_bonus_sale > 0
                AND sk_date BETWEEN 20210208 AND 20210630
            GROUP BY 1,2,3,4,5,6,7
        ),
        cluster_promo_bonus AS(
            SELECT 
                sk_date,
                'pb_datamart' AS table_origin,
                CASE 
                    WHEN affiliate_type = 'Standard'
                        THEN 'Indica Aí - General'
                    WHEN affiliate_type = 'Agent'
                        THEN 'Indica Aí - Agents'
                    ELSE affiliate_type
                END AS mkt_origin,
                city_group,
                'engagement' AS vertical,
                'Promotional Bonus' AS source,
                'rent' AS business_context,
                SUM(final_bonus_rent) AS cost
            FROM 
                dw_datamarts.performance_marketing_cluster_promotional_bonus_costs
            WHERE final_bonus_rent > 0
            AND sk_date >= 20210701
            GROUP BY 1,2,3,4,5,6,7
            
            UNION ALL
            
            SELECT 
                sk_date,
                'pb_datamart' AS table_origin,
                CASE 
                    WHEN affiliate_type = 'Standard' THEN 'Indica Aí - General'
                    WHEN affiliate_type = 'Agent' THEN 'Indica Aí - Agents'
                    ELSE affiliate_type
                END AS mkt_origin,
                city_group,
                'engagement' AS vertical,
                'Promotional Bonus' AS source,
                'sale' AS business_context,
                SUM(final_bonus_sale) AS cost
            FROM 
                dw_datamarts.performance_marketing_cluster_promotional_bonus_costs
            WHERE final_bonus_sale > 0
            AND sk_date >= 20210701
            GROUP BY 1,2,3,4,5,6,7
        ),
    extra_promotional_bonus_rent AS(
        SELECT
            CAST(date_format(DATE(NULLIF(eb.date,'')), 'yyyyMMdd') as BIGINT) AS sk_date,
            'extra_bonus' AS table,
            CASE
                WHEN dua.type = 'Standard' THEN 'Indica Aí - General'
                WHEN dua.type = 'Agent' THEN 'Indica Aí - Agents'
                ELSE dua.type
            END AS mkt_origin,
            eb.city_group,
            'engagement' AS vertical,
            'Promotional Bonus' AS source,
            'rent' AS business_context,
            SUM(CASE WHEN LOWER(eb.business_context) = 'rent' THEN bonus WHEN LOWER(eb.business_context) = 'hybrid' THEN 0.5 * bonus ELSE 0 END) AS cost
        FROM
            datalake_gsheets_clean.affiliates_extra_user_bonus eb
        LEFT JOIN dw_public.dim_user_affiliate dua
            ON dua.sk_user = eb.sk_user
        WHERE LOWER(eb.business_context) IN ('rent', 'hybrid')
        GROUP BY 1,2,3,4,5,6,7
    ),
    extra_promotional_bonus_sale AS(
        SELECT
            CAST(date_format(DATE(NULLIF(eb.date,'')), 'yyyyMMdd') as BIGINT) AS sk_date,
            'extra_bonus' AS table,
            CASE
                WHEN dua.type = 'Standard' THEN 'Indica Aí - General'
                WHEN dua.type = 'Agent' THEN 'Indica Aí - Agents'
                ELSE dua.type
            END AS mkt_origin,
            eb.city_group,
            'engagement' AS vertical,
            'Promotional Bonus' AS source,
            'sale' AS business_context,
            SUM(CASE WHEN LOWER(eb.business_context) = 'sale' THEN bonus WHEN LOWER(eb.business_context) = 'hybrid' THEN 0.5 * bonus ELSE 0 END) AS cost
        FROM
            datalake_gsheets_clean.affiliates_extra_user_bonus eb
        LEFT JOIN dw_public.dim_user_affiliate dua
            ON dua.sk_user = eb.sk_user
        WHERE LOWER(eb.business_context) IN ('sale', 'hybrid')
        GROUP BY 1,2,3,4,5,6,7
    )
        SELECT * FROM segmentation_promo_bonus
        UNION ALL 
        SELECT * FROM cluster_promo_bonus
        UNION ALL
        SELECT * FROM extra_promotional_bonus_rent
        UNION ALL
        SELECT * FROM extra_promotional_bonus_sale
    ),
    ia_fact_affiliate_transposed AS (
        SELECT
            id_date AS sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Commission Listing' AS source,
            NULL as business_context,
            commission_listing_cost AS cost
        FROM
            datalake_affiliates_cost_attributions.affiliates_cost_attributions
        WHERE
            id_date < 20210125
        UNION ALL
        SELECT
            id_date AS sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Commission Rent' AS source,
            NULL as business_context,
            commission_rent_cost AS cost
        FROM
            datalake_affiliates_cost_attributions.affiliates_cost_attributions
        WHERE
            id_date < 20210125
        UNION ALL
        SELECT
            id_date AS sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'acquisition' AS vertical,
            'Commission MGM' AS source,
            NULL as business_context,
            commission_mgm_cost AS cost
        FROM
            datalake_affiliates_cost_attributions.affiliates_cost_attributions
        WHERE
            id_date < 20210125
        UNION ALL
        SELECT
            id_date AS sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin, 
            city_group,
            'engagement' AS vertical,
            'Commission Tradecom' AS source,
            NULL as business_context,
            commission_tradecom_cost AS cost
        FROM
            datalake_affiliates_cost_attributions.affiliates_cost_attributions
        UNION ALL
        SELECT
            id_date AS sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Promotional Bonus' AS source,
            NULL as business_context,
            promotional_bonus_cost AS cost
        FROM
            datalake_affiliates_cost_attributions.affiliates_cost_attributions
        WHERE
            id_date < 20210208
        UNION ALL
        SELECT
            id_date AS sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Notification' AS source,
            NULL as business_context,
            notification_cost AS cost
        FROM
            datalake_affiliates_cost_attributions.affiliates_cost_attributions
        
        UNION ALL
        SELECT
            id_date AS sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Other' AS source,
            NULL as business_context,
            other_cost AS cost
        FROM
            datalake_affiliates_cost_attributions.affiliates_cost_attributions
    ),
    ia_provisioned_costs AS (
        SELECT
            CAST(date_format(DATE(dt_created), 'yyyyMMdd') as BIGINT) AS sk_date,
            'sheets' AS table_origin,
            CAST(NULLIF(mkt_origin,'') AS STRING) AS mkt_origin,
            CAST(NULLIF(city_group,'') AS STRING) AS city_group,
            CAST(NULL AS STRING) AS vertical,
            CAST(NULLIF(source,'') AS STRING) AS source,
            NULL as business_context,
            CAST(NULLIF(cost,'') AS FLOAT) AS cost
        FROM
            datalake_gsheets_clean.provisioned_costs_import
    ),
    ia_sale_costs AS (
        WITH lbc_rent AS (
            SELECT 
                DISTINCT cast(id_house AS BIGINT) AS id_house,
                cast(ts_first_publication AS DATE) AS dt_first_publication
            FROM
                datalake_ebdb_clean.listing_business_context AS lbc 
            WHERE
                business_context ='RENT'
                AND ts_first_publication IS NOT NULL
        ),
        listings_sale AS( 
            SELECT
                sk_first_listing_date AS sk_first_listing_date,
                lf.sk_user_lead_affiliate AS id_user,
                CAST((lf.sk_house_listing/1000) AS INT) AS id_house,
                CASE 
                    WHEN lf.listing_rent_status = 'Once Published'
                        THEN true 
                    ELSE false 
                END AS listing_rent,
                dr.city_group,
                lf.mkt_origin,
                lf.affiliate_type,
                CASE
                    WHEN date_trunc('month', rbc.dt_first_publication) = date_trunc('month', dd.date) 
                        THEN true
                    ELSE false 
                END AS flag_publication_sale_and_rent_same_month
            FROM dw_sale.fact_listing_flows AS lf 
            LEFT JOIN dw_public.dim_date AS dd  
                ON dd.sk_date = lf.sk_first_listing_date
            LEFT JOIN dw_public.dim_region AS dr 
                ON dr.sk_region = lf.sk_region
            LEFT JOIN datalake_ebdb_clean.listing_business_context AS lbc 
                ON lbc.id_house = CAST((lf.sk_house_listing/1000) AS INT)
                AND lbc.business_context = 'SALE'
            LEFT JOIN lbc_rent AS rbc 
                ON rbc.id_house = CAST((lf.sk_house_listing/1000) AS INT)
            WHERE lf.sk_first_listing_date BETWEEN 0 AND 20210630
                AND lf.sk_user_lead_affiliate > 0
                AND lf.mkt_origin IN ('Doorman', 'Indica Aí - Agents', 'Indica Aí - General')
                OR(lf.sk_first_listing_date >= 20210701
                    AND lf.sk_user_lead_affiliate > 0
                    AND lf.mkt_origin IN ('Doorman', 'Indica Aí - Agents', 'Indica Aí - General')
                    AND lf.sk_user_lead_affiliate NOT IN (360754,912255,1711931,2257503))
        )
        (SELECT
            sk_first_listing_date,
            'sale_flows' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Comission Listing' AS source,
            CASE 
                WHEN flag_publication_sale_and_rent_same_month = 'false'
                    THEN 'sale' 
                ELSE 'hybrid'
            END AS business_context,
            CASE 
                WHEN flag_publication_sale_and_rent_same_month = 'false'
                    THEN (COUNT(id_house))*100 
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
            'sale_flows' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Comission Listing' AS source,
            CASE 
                WHEN flag_publication_sale_and_rent_same_month = 'false'
                    THEN 'sale' 
                ELSE 'hybrid'
            END AS business_context,
            CASE 
                WHEN flag_publication_sale_and_rent_same_month = 'false'
                    THEN (COUNT(id_house))*100 
                ELSE (COUNT(id_house))*50
            END AS cost
        FROM 
            listings_sale
        WHERE 
            mkt_origin != 'Doorman'
            AND sk_first_listing_date < 20210125
        GROUP BY 1,2,3,4,5,6,7, flag_publication_sale_and_rent_same_month
        )
    ),
    doorman_rent_costs AS (
        WITH lbc_sale AS (
            SELECT 
                DISTINCT CAST(id_house AS bigint) AS id_house,
                CAST(ts_first_publication AS date) AS dt_first_publication
            FROM 
                datalake_ebdb_clean.listing_business_context AS lbc 
            WHERE
                business_context ='SALE'
                AND ts_first_publication IS NOT NULL
        ),
        listings_sale AS( 
            SELECT
                sk_first_listing_date AS sk_first_listing_date,
                lf.sk_user_lead_affiliate AS id_user,
                CAST((lf.sk_house_listing/1000) AS INT) AS id_house,
                dr.city_group,
                lf.mkt_origin,
                lf.affiliate_type,
                CASE
                    WHEN date_trunc('month', sbc.dt_first_publication) = date_trunc('month', dd.date) 
                        THEN true
                    ELSE false 
                END AS flag_publication_sale_and_rent_same_month
            FROM
                dw_public.fact_house_listing_flows AS lf 
            LEFT JOIN dw_public.dim_date AS dd  
                ON dd.sk_date = lf.sk_first_listing_date
            LEFT JOIN dw_public.dim_region AS dr 
                ON dr.sk_region = lf.sk_region
            LEFT JOIN datalake_ebdb_clean.listing_business_context AS lbc 
                ON lbc.id_house = CAST((lf.sk_house_listing/1000) AS INT)
                AND lbc.business_context = 'RENT'
            LEFT JOIN lbc_sale AS sbc 
                ON sbc.id_house = CAST((lf.sk_house_listing/1000) AS INT)
            WHERE 
                lf.sk_first_listing_date BETWEEN 0 AND 20210630
                AND lf.sk_user_lead_affiliate > 0
                AND lf.mkt_origin = 'Doorman'
                OR(lf.sk_first_listing_date >= 20210701
                    AND lf.sk_user_lead_affiliate > 0
                    AND lf.mkt_origin = 'Doorman'
                    AND lf.sk_user_lead_affiliate NOT IN (360754,912255,1711931,2257503))
        )
        SELECT
            sk_first_listing_date,
            'rent_flows' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Comission Listing' AS source,
            CASE 
                WHEN flag_publication_sale_and_rent_same_month = 'false'
                    THEN 'rent' 
                ELSE 'hybrid'
            END AS business_context,
            CASE 
                WHEN flag_publication_sale_and_rent_same_month = 'false'
                    THEN (COUNT(id_house))*100 
                ELSE (COUNT(id_house))*50
            END AS cost
        FROM 
            listings_sale
        WHERE sk_first_listing_date >= 20210125
        GROUP BY 1,2,3,4,5,6,7, flag_publication_sale_and_rent_same_month
    ),
    manual_tax AS (
        SELECT
            CAST(REPLACE(dt_tax_cost, '-', '') AS BIGINT) AS sk_date,
            'manual_tax' AS table_origin,
            mkt_origin,
            city_group,
            vertical,
            source,
            business_context,
            costs
        FROM
            datalake_gsheets_clean.indicaai_tax_costs
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
        UNION ALL
        SELECT * FROM ia_sale_costs
        UNION ALL
        SELECT * FROM doorman_rent_costs
        UNION ALL
        SELECT * FROM manual_tax
    ),
    base AS (
        SELECT
            dd.date,
            CAST(dd.week_start AS STRING) week_start,
            dd.year_month,
            iac.table_origin,
            iac.mkt_origin,
            iac.city_group,
            iac.vertical,
            iac.source,
            iac.business_context,
            SUM(iac.cost) AS costs,
            date_part("month",dd.date) month_num
        FROM
            ia_total_cost AS iac
        JOIN dw_public.dim_date AS dd 
            ON dd.sk_date = iac.sk_date
        WHERE
            iac.cost IS NOT NULL
            AND dd.month_start >= date_trunc('month',CURRENT_DATE) - interval '72 month'
         GROUP BY 1,2,3,4,5,6,7,8,9,11
         HAVING costs>0
     ),
     
    sale_rent_cities AS (
        SELECT DISTINCT
            dr.city_group
        FROM dw_sale.fact_listings AS sfl
        INNER JOIN dw_public.dim_region AS dr 
            ON sfl.sk_region = dr.sk_region
    )
     
     SELECT 
         date, 
         base.city_group,
         business_context,
         mkt_origin,
         SUM(costs) AS costs
     FROM base
     LEFT JOIN sale_rent_cities
        ON base.city_group = sale_rent_cities.city_group
     WHERE vertical != 'acquisition' 
        OR vertical IS NULL
        OR (vertical = 'acquisition' AND date <= DATE('2021-12-31'))
        OR (vertical = 'acquisition' AND sale_rent_cities.city_group IS NULL)
     GROUP BY 1, 2, 3, 4

     UNION ALL

     --RENT

     SELECT 
         date, 
         base.city_group,
         'rent' AS business_context,
         mkt_origin,
         SUM(costs) * 0.80 AS costs
     FROM base
     INNER JOIN sale_rent_cities
        ON base.city_group = sale_rent_cities.city_group
     WHERE vertical = 'acquisition'
        AND date > DATE('2021-12-31')
     GROUP BY 1, 2, 3, 4

     UNION ALL

     --SALE

         SELECT 
         date, 
         base.city_group,
         'sale' AS business_context,
         mkt_origin,
         SUM(costs) * 0.20 AS costs
     FROM base
     INNER JOIN sale_rent_cities
        ON base.city_group = sale_rent_cities.city_group
     WHERE vertical = 'acquisition'
        AND date > DATE('2021-12-31')
     GROUP BY 1, 2, 3, 4
),
affiliates_sale_cost AS (
    SELECT 
        date AS dt_cost, 
        city_group, 
        'Sale' AS business,
        'Supply' AS planning_mkt_level1, 
        'Affiliates' AS planning_mkt_level2,
        replace(mkt_origin,' Sale','') AS planning_mkt_level3,
        sum(costs) AS costs
    FROM
        affiliates
    WHERE
        LOWER(business_context) = 'sale' OR (business_context IS NULL AND mkt_origin IN ('Doorman Sale','Indica Aí - Agents Sale','Indica Aí - General Sale'))    GROUP BY 1, 2, 3, 4, 5, 6
),
supply_affiliates_cost AS (
    SELECT 
        date AS dt_cost, 
        city_group, 
        'Rental' as business,
        'Supply' AS planning_mkt_level1, 
        'Affiliates' AS planning_mkt_level2,
        mkt_origin AS planning_mkt_level3,
        sum(costs) AS costs
    FROM
        affiliates
    WHERE
        LOWER(business_context) = 'rent' OR (business_context IS NULL AND mkt_origin IN ('Doorman','Indica Aí - Agents','Indica Aí - General'))
    GROUP BY 1, 2, 3, 4, 5, 6
),
supply_affiliates_cost_hybrid_sale AS (
    SELECT 
        date AS dt_cost, 
        city_group, 
        'Sale' as business,
        'Supply' AS planning_mkt_level1, 
        'Affiliates' AS planning_mkt_level2,
        mkt_origin AS planning_mkt_level3,
        sum(costs/2) AS costs
    FROM affiliates
    WHERE LOWER(business_context) = 'hybrid' 
    GROUP BY 1, 2, 3, 4, 5, 6
),
supply_affiliates_cost_hybrid_rental AS (
    SELECT 
        date AS dt_cost, 
        city_group, 
        'Rental' as business,
        'Supply' AS planning_mkt_level1, 
        'Affiliates' AS planning_mkt_level2,
        mkt_origin AS planning_mkt_level3,
        sum(costs/2) AS costs
    FROM affiliates
    WHERE LOWER(business_context) = 'hybrid' 
    GROUP BY 1, 2, 3, 4, 5, 6
),
supply_landlords_cost AS (
    SELECT
        dbt.date AS dt_cost,
        co.city_group,
        'Rental' as business,
        'Supply' AS planning_mkt_level1,
        'Landlords' AS planning_mkt_level2,
        CASE
            WHEN mkt_origin = 'Owner PWA'
                THEN 'PWA - '||mkt_channel
            ELSE mkt_origin
        END AS planning_mkt_level3,
        SUM(co.cost) AS costs
    FROM
        datalake_marketing_costs.daily_costs AS co
    JOIN dw_public.dim_date AS dbt
        ON dbt.sk_date = co.id_date
    WHERE
        co.funnel_side = 'supply'
        AND dbt.date BETWEEN DATE('2020-01-01') AND CURRENT_DATE - INTERVAL "1" day
        AND co.mkt_origin IN ('Owner PWA','Price Calculator','New Channels','Test')
        AND co.mkt_channel != 'Girafa'
    GROUP BY 1, 2, 3, 4, 5, 6
),
branded_costs AS (
    SELECT 
        dbt.date AS dt_cost,
        bmc.city_group,
        CASE
            WHEN business_context = 'rent'
                THEN 'Rental'
            WHEN business_context = 'sale'
                THEN 'Sale'
        END AS business,
        'Branded' AS planning_mkt_level1,
        'Branded' AS planning_mkt_level2,
        CASE WHEN bmc.mkt_channel = 'Organic' THEN 'Branding' ELSE bmc.mkt_channel END AS planning_mkt_level3,
        CAST(sum(replace(replace(nullif(bmc.cost,''),'$',''),',','')) AS FLOAT) AS costs
    FROM 
        datalake_gsheets_clean.offline_and_branding_marketing_costs AS bmc
        JOIN dw_public.dim_date AS dbt
            ON CAST(bmc.sk_date AS INT) = dbt.sk_date
    GROUP BY 1, 2, 3, 4, 5, 6
    UNION ALL
    SELECT
        dd.date AS dt_cost,
        c.city_group,
        CASE WHEN c.cost_center ilike '%sale%' THEN 'Sale'
            ELSE 'Rental' END AS business,
        'Branded' AS planning_mkt_level1,
        'Branded' AS planning_mkt_level2,
        c.cost_category AS planning_mkt_level3,
        SUM(c.cost) AS costs
    FROM
        datalake_marketing_costs.offline_manual_costs AS c
        JOIN dw_public.dim_date dd
            ON dd.sk_date = c.id_date
    WHERE
        c.ts_entry>=DATE('2020-01-01')
    GROUP BY 1,2,3,4,5,6
),
demand_sale_cost AS (
    SELECT
        dbt.date AS dt_cost,
        co.city_group AS city_group,
        'Sale' AS business,
        'Demand' AS planning_mkt_level1,
        CASE
            WHEN co.mkt_channel LIKE '%Paid%' OR co.mkt_channel = 'Performance Max'
                THEN 'Paid'
            ELSE co.mkt_channel
            END AS planning_mkt_level2,
        co.mkt_medium AS planning_mkt_level3,
        SUM(co.cost) AS costs
    FROM
        datalake_marketing_costs.daily_costs AS co
    JOIN dw_public.dim_date AS dbt
        ON dbt.sk_date = co.id_date
    WHERE co.funnel_side = 'demand'
        AND dbt.date BETWEEN DATE('2019-01-01') AND CURRENT_DATE - INTERVAL "1" day
        AND co.mkt_medium != 'Social'
        AND co.mkt_origin = 'Tenants PWA - Sale'
        AND co.mkt_channel != 'Paid Traffic'
        AND coalesce(account_name, '') != 'quintoandar_display_and_video_acquisition'
    GROUP BY 1, 2, 3, 4, 5, 6
),
supply_sale_cost AS (
    SELECT
        dbt.date AS dt_cost,
        co.city_group AS city_group,
        'Sale' AS business,
        'Supply' AS planning_mkt_level1,
        'Landlords' AS planning_mkt_level2,
        co.mkt_origin AS planning_mkt_level3,
        sum(co.cost) AS costs
    FROM
        datalake_marketing_costs.daily_costs AS co
    JOIN dw_public.dim_date dbt
        ON dbt.sk_date = co.id_date
    WHERE
        co.account_name IN ('quintoandar_supply_sale_display', 'quintoandar_supply_sale', 'supply_landlords_sale', 'supply_landlords') 
        AND co.mkt_origin IN ('Owner PWA - Sale', 'Price Calculator - Sale')
    GROUP BY 1,2,3,4,5,6
),
supply_ciq_cost AS (
    SELECT
        dbt.date AS dt_cost,
        co.city_group AS city_group,
        'Rental' AS business,
        'Supply' AS planning_mkt_level1,
        'Affiliates' AS planning_mkt_level2,
        co.mkt_origin AS planning_mkt_level3,
        sum(co.cost) AS costs
    FROM
        datalake_marketing_costs.daily_costs AS co
    JOIN
        dw_public.dim_date AS dbt ON dbt.sk_date = co.id_date
    WHERE
        co.mkt_origin = 'CIQ'
    GROUP BY 1, 2, 3, 4, 5, 6
),
supply_ciq_cost_comission AS (
    SELECT
        data AS dt_cost,
        co.city AS city_group,
        'Rental' AS business,
        'Supply' AS planning_mkt_level1,
        'Affiliates' AS planning_mkt_level2,
        'CIQ' AS planning_mkt_level3,
        SUM(co.total_costs_ciq_full_for_rent) AS costs
    FROM
        datalake_gsheets_clean.ciq_costs AS co
    GROUP BY 1,2,3,4,5,6
),
supply_ciq_cost_comission_sale AS (
    SELECT
        data AS dt_cost,
        co.city AS city_group,
        'Sale' AS business,
        'Supply' AS planning_mkt_level1,
        'Affiliates' AS planning_mkt_level2,
        'CIQ' AS planning_mkt_level3,
        SUM(co.total_costs_ciq_full_for_sale) AS costs
    FROM
        datalake_gsheets_clean.ciq_costs AS co
    WHERE
        LOCATE(comission_listing_fs, '#') = 0
    GROUP BY 1,2,3,4,5,6
),
supply_spinver_cost AS(
    WITH spinver_costs AS(
        WITH spinver_qualifieds AS(
            SELECT
                dd.month_start,
                dd.year_month,
                dr.city_group,
                COUNT(DISTINCT (CASE WHEN llf.context_qualified = 'Rent' THEN llf.sk_house_listing_flow ELSE NULL END)) rent_qualified,
                COUNT(DISTINCT (CASE WHEN llf.context_qualified = 'Sale' THEN llf.sk_house_listing_flow ELSE NULL END)) sale_qualified,
                COUNT(DISTINCT (CASE WHEN llf.context_qualified = 'Hybrid' THEN llf.sk_house_listing_flow ELSE NULL END)) hybrid_qualified,
                COUNT(DISTINCT llf.sk_house_listing_flow ) total_qualified
            FROM dw_datamarts.lead_listing_flows llf
            LEFT JOIN dw_public.dim_date dd
                ON dd.sk_date = llf.sk_qualified_date
            LEFT JOIN dw_public.dim_region dr
                ON dr.sk_region = llf.sk_region
            WHERE aux_rn_qualified = 1
            AND llf.sk_qualified_date > 0
            AND llf.sk_user_lead_affiliate IN (360754,912255,1711931,2257503)
            AND dd.date >= DATE('2021-07-01')
            AND dr.city_group IS NOT NULL
            GROUP BY 1,2,3
        ),
        operation_costs_by_qualified AS(
            SELECT
                month_start,
                SUM(total_qualified),
                CASE
                    WHEN SUM(total_qualified) BETWEEN 0 AND 1600 THEN CAST(40 AS FLOAT)
                    WHEN SUM(total_qualified) BETWEEN 1601 AND 1900 THEN CAST(55 AS FLOAT)
                    WHEN SUM(total_qualified) BETWEEN 1901 AND 2300 THEN CAST(61 AS FLOAT)
                    WHEN SUM(total_qualified) BETWEEN 2301 AND 2700 THEN CAST(67 AS FLOAT)
                    WHEN SUM(total_qualified) BETWEEN 2701 AND 3200 THEN CAST(75 AS FLOAT)
                    WHEN SUM(total_qualified) BETWEEN 3201 AND 3900 THEN CAST(83 AS FLOAT)
                    WHEN SUM(total_qualified) > 3900 THEN CAST(94 AS FLOAT)
                    ELSE NULL
                END AS operation_cost_by_qualified
            FROM spinver_qualifieds
            GROUP BY 1
        ),
        operation_costs AS (
            WITH rent_op_costs AS(
                SELECT
                sq.month_start,
                sq.year_month,
                sq.city_group,
                'Rent' AS business_context,
                sq.rent_qualified AS qualifieds,
                CASE
                    WHEN sq.city_group in ('Belo Horizonte', 'RMSP', 'Rio de Janeiro', 'Porto Alegre') THEN sq.hybrid_qualified/2.0
                    ELSE sq.hybrid_qualified
                END AS hybrid_qualifieds,
                CASE
                    WHEN sq.city_group in ('Belo Horizonte', 'RMSP', 'Rio de Janeiro', 'Porto Alegre') THEN CAST(((sq.rent_qualified + (sq.hybrid_qualified/2.0)) * obq.operation_cost_by_qualified) AS FLOAT)
                    ELSE CAST(((sq.rent_qualified + (sq.hybrid_qualified)) * obq.operation_cost_by_qualified) AS FLOAT)
                END AS operation_cost
            FROM
                spinver_qualifieds sq
            LEFT JOIN operation_costs_by_qualified obq
                ON sq.month_start = obq.month_start
            ),
            sale_op_costs AS(
                SELECT
                sq.month_start,
                sq.year_month,
                sq.city_group,
                'Sale' AS business_context,
                sq.sale_qualified AS qualifieds,
                CASE
                    WHEN sq.city_group in ('Belo Horizonte', 'RMSP', 'Rio de Janeiro', 'Porto Alegre') THEN sq.hybrid_qualified/2.0
                    ELSE 0
                END AS hybrid_qualifieds,
                CASE
                    WHEN sq.city_group in ('Belo Horizonte', 'RMSP', 'Rio de Janeiro', 'Porto Alegre') THEN CAST(((sq.sale_qualified + (sq.hybrid_qualified/2.0)) * obq.operation_cost_by_qualified) AS FLOAT)
                    ELSE 0
                END AS operation_cost
            FROM
                spinver_qualifieds sq
            LEFT JOIN operation_costs_by_qualified obq
                ON sq.month_start = obq.month_start
            )
        SELECT * FROM rent_op_costs
        union all
        SELECT * FROM sale_op_costs
        ),
        exclusivity_costs AS (
            WITH ex_cost_calc AS (
                SELECT
                    month_start,
                    CASE
                        WHEN SUM(rent_qualified + hybrid_qualified) BETWEEN 0 AND 1100 THEN SUM(rent_qualified + sale_qualified + hybrid_qualified) * 64.5
                        WHEN SUM(rent_qualified + hybrid_qualified) BETWEEN 1101 AND 1300 THEN 100000
                        WHEN SUM(rent_qualified + hybrid_qualified) BETWEEN 1301 AND 1450 THEN 140000
                        WHEN SUM(rent_qualified + hybrid_qualified) > 1450 THEN 180000
                        ELSE NULL
                    END as rent_spinver_exclusivity_cost,
                    CASE
                        WHEN SUM(sale_qualified + hybrid_qualified) BETWEEN 0 AND 450 THEN SUM(rent_qualified + sale_qualified + hybrid_qualified) * 64.5
                        WHEN SUM(sale_qualified + hybrid_qualified) BETWEEN 451 AND 550 THEN 100000
                        WHEN SUM(sale_qualified + hybrid_qualified) BETWEEN 551 AND 610 THEN 140000
                        WHEN SUM(sale_qualified + hybrid_qualified) > 611 THEN 180000
                        ELSE NULL
                    END AS sale_spinver_exclusivity_cost,
                    SUM(rent_qualified + sale_qualified + hybrid_qualified) AS calc_qualified
                FROM spinver_qualifieds
                GROUP BY 1
            )
            SELECT
                ec.month_start,
                sq.year_month,
                sq.city_group,
                CASE
                    WHEN ec.calc_qualified = 0 THEN 0
                    WHEN ec.rent_spinver_exclusivity_cost < ec.sale_spinver_exclusivity_cost OR ec.sale_spinver_exclusivity_cost = 0 THEN ec.rent_spinver_exclusivity_cost/ec.calc_qualified
                    ELSE ec.sale_spinver_exclusivity_cost/ec.calc_qualified
                END AS exclusivity_cost_per_qualified
            FROM
                ex_cost_calc ec
            LEFT JOIN spinver_qualifieds sq
                on ec.month_start = sq.month_start
        )
        SELECT
            oc.month_start,
            oc.year_month,
            oc.city_group,
            oc.business_context,
            oc.qualifieds,
            oc.hybrid_qualifieds,
            (oc.qualifieds + oc.hybrid_qualifieds) AS total_qualified,
            oc.operation_cost,
            (ef.exclusivity_cost_per_qualified * (oc.qualifieds + oc.hybrid_qualifieds)) AS exclusivity_fee
        FROM
            operation_costs oc
        JOIN exclusivity_costs ef
            ON oc.month_start = ef.month_start
                AND oc.year_month = ef.year_month
                AND oc.city_group = ef.city_group
        WHERE qualifieds > 0
    )
    SELECT
        month_start AS dt_cost,
        city_group,
        business_context AS business,
        'Supply' AS planning_mkt_level1,
        'Affiliates' AS planning_mkt_level2,
        'Partners' AS planning_mkt_level3,
        SUM(CAST(operation_cost AS FLOAT) + CAST(exclusivity_fee AS FLOAT)) AS costs
    FROM
        spinver_costs
    WHERE month_start <= DATE('2022-01-01')
    GROUP BY 1,2,3,4,5,6
),
cost_union AS (
    SELECT * FROM demand_cost
    UNION ALL
    SELECT * FROM supply_affiliates_cost     
    UNION ALL
    SELECT * FROM supply_landlords_cost
    UNION ALL
    SELECT * FROM branded_costs
    UNION ALL
    SELECT * FROM demand_sale_cost
    UNION ALL
    SELECT * FROM supply_sale_cost
    UNION ALL
    SELECT * FROM affiliates_sale_cost
    UNION ALL
    SELECT * FROM supply_affiliates_cost_hybrid_sale
    UNION ALL
    SELECT * FROM supply_affiliates_cost_hybrid_rental
    UNION ALL
    SELECT * FROM supply_ciq_cost
    UNION ALL
    SELECT * FROM supply_ciq_cost_comission
    UNION ALL
    SELECT * FROM supply_ciq_cost_comission_sale
    UNION ALL
    SELECT * FROM supply_spinver_cost
)
SELECT 
    CAST(dt_cost AS STRING) AS dt_cost, 
    CAST(date_format(date_trunc('week',dt_cost), 'yyyy-MM-dd') as STRING) AS week_start,
    CAST(date_format(date_trunc('month',dt_cost), 'yyyy-MM-dd') as STRING) AS month_start,
    CASE
        WHEN date_part('month',date_trunc('quarter',dt_cost)) = 4
            THEN 2  
         WHEN date_part('month',date_trunc('quarter',dt_cost)) = 7
            THEN 3  
         WHEN date_part('month',date_trunc('quarter',dt_cost)) = 10
            THEN 4 
         ELSE date_part('month',date_trunc('quarter',dt_cost))
    END AS quarter,
    CASE
        WHEN date_part('month',dt_cost) <= 6
            THEN 1
        ELSE 2
    END AS halfyear, 
    CASE
        WHEN cst.city_group IS NULL
            THEN 'Not Mapped'
        ELSE cst.city_group
    END AS city_group,
    dr.tier,
    CASE 
        WHEN cst.business ILIKE '%rent%' 
            THEN 'Rental' 
        ELSE cst.business 
    END AS business,
    planning_mkt_level1,
    CASE
        WHEN planning_mkt_level3 = 'Online Classifieds'
            THEN 'Online Classifieds'
        WHEN planning_mkt_level3 IN ('Portals', 'Display', 'Retargeting', 'SEM non-branded')
            THEN 'Paid'
        WHEN planning_mkt_level3 = 'CIQ'
            THEN 'Affiliates'
        ELSE planning_mkt_level2
    END AS planning_mkt_level2,
    planning_mkt_level3,
    sum(costs) AS costs,
    date_part('month',dt_cost) AS month_num
FROM
    cost_union AS cst
LEFT JOIN (
    SELECT
        DISTINCT city_group,
        tier
    FROM
        dw_public.dim_region
    WHERE tier IS NOT NULL
) AS dr
    ON cst.city_group = dr.city_group
WHERE
    dt_cost < current_date
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13