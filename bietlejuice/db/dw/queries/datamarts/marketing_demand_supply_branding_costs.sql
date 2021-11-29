WITH
demand_cost AS (
    SELECT
        dbt.date AS dt_cost,
        co.city_group AS city_group,
        'Rental' AS business,
        'Demand' AS planning_mkt_level1,
        CASE
            WHEN co.mkt_channel = 'Online Paid'
                THEN 'Paid'
            ELSE co.mkt_channel
            END AS planning_mkt_level2,
        co.mkt_medium AS planning_mkt_level3,
        SUM(co.cost) AS costs
    FROM
        marketing.fact_marketing_daily_costs AS co
    JOIN dim_date AS dbt
        ON dbt.sk_date = co.sk_date
    WHERE
        co.funnel_side = 'demand'
        AND dbt.date BETWEEN '2019-01-01' AND CURRENT_DATE - 1
        AND co.mkt_medium != 'Branding'
        AND co.mkt_origin = 'Tenants PWA'
    GROUP BY 1, 2, 3, 4, 5, 6
),
affiliates AS (
    WITH 
    ia_fact_cost AS (
        SELECT
            fc.sk_date, 
            'fact_cost' AS table_origin, 
            mkt_origin, 
            fc.city_group,
            CASE
                WHEN fc.utm_campaign ~* '(acq)' OR fc.mkt_source = 'Bing'
                    THEN 'acquisition'
                WHEN fc.utm_campaign ~* '(eng)'
                    THEN 'engagement'
                ELSE NULL
            END AS vertical,
            CASE
                WHEN fc.mkt_source IN ('Twilio', 'Movile')
                    THEN 'Notification'
                ELSE mkt_source
            END AS source, 
            NULL AS business_context,
            fc.cost
        FROM
            marketing.fact_marketing_daily_costs AS fc
        WHERE
            fc.mkt_origin = 'Indica Aí - General' 
    ),
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
                quintoandar.fact_affiliate_costs AS f
            LEFT JOIN quintoandar.dim_affiliate_cost AS d
                ON f.sk_rh_accounting_entry = d.sk_rh_accounting_entry
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
                WHEN cc.cost_center_code = 'C046'
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
                datamarts.performance_marketing_promotional_bonus_costs_daily
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
                datamarts.performance_marketing_promotional_bonus_costs_daily
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
                datamarts.performance_marketing_cluster_promotional_bonus_costs
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
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Commission Listing' AS source,
            NULL as business_context,
            commission_listing AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        WHERE
            sk_date < 20210125

        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Commission Rent' AS source,
            NULL as business_context,
            commission_rent AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        WHERE
            sk_date < 20210125

        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'acquisition' AS vertical,
            'Commission MGM' AS source,
            NULL as business_context,
            commission_mgm AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        WHERE
            sk_date < 20210125

        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin, city_group,
            'engagement' AS vertical,
            'Commission Tradecom' AS source,
            NULL as business_context,
            commission_tradecom AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions

        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Promotional Bonus' AS source,
            NULL as business_context,
            promotional_bonus AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        WHERE
            sk_date < 20210208

        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Notification' AS source,
            NULL as business_context,
            notification AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions
        
        UNION ALL

        SELECT
            sk_date,
            'fact_affiliate' AS table_origin,
            mkt_origin,
            city_group,
            'engagement' AS vertical,
            'Other' AS source,
            NULL as business_context,
            other AS cost
        FROM
            marketing.fact_affiliate_daily_cost_attributions 
    ),
    ia_provisioned_costs AS (
        SELECT
            TO_CHAR(NULLIF(date,'')::DATE,'yyyymmdd')::BIGINT AS sk_date,
            'sheets' AS table_origin,
            NULLIF(cost_origin,'')::VARCHAR AS mkt_origin,
            NULLIF(city_group,'')::VARCHAR AS city_group,
            NULL::text AS vertical,
            NULLIF(cost_type,'')::VARCHAR AS source,
            NULL as business_context,
            NULLIF(cost,'')::FLOAT AS cost
        FROM
            datalake_raw.gsheets_provisioned_costs_import
    ),
    ia_sale_costs AS (
        WITH lbc_rent AS (
            SELECT 
                DISTINCT cast(id_house AS BIGINT) AS id_house,
                cast(ts_first_publication AS DATE) AS dt_first_publication
            FROM
                datalake_ebdb_clean_prod.listing_business_context AS lbc 
            WHERE
                business_context ='RENT'
                AND ts_first_publication IS NOT NULL
        ),
        listings_sale AS( 
            SELECT
                sk_first_listing_date AS sk_first_listing_date,
                lf.sk_user_lead_affiliate AS id_user,
                lf.sk_house_listing/1000 AS id_house,
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
            FROM sale.fact_listing_flows AS lf 
            LEFT JOIN dim_date AS dd  
                ON dd.sk_date = lf.sk_first_listing_date
            LEFT JOIN dim_region AS dr 
                ON dr.sk_region = lf.sk_region
            LEFT JOIN datalake_ebdb_clean_prod.listing_business_context AS lbc 
                ON lbc.id_house = lf.sk_house_listing/1000
                AND lbc.business_context = 'SALE'
            LEFT JOIN lbc_rent AS rbc 
                ON rbc.id_house = lf.sk_house_listing/1000  
            WHERE lf.sk_first_listing_date > 0
                AND lf.sk_user_lead_affiliate > 0
                AND lf.mkt_origin IN ('Doorman', 'Indica Aí - Agents', 'Indica Aí - General')
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
            mkt_origin <> 'Doorman'
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
                datalake_ebdb_clean_prod.listing_business_context AS lbc 
            WHERE
                business_context ='SALE'
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
                CASE
                    WHEN date_trunc('month', sbc.dt_first_publication) = date_trunc('month', dd.date) 
                        THEN true
                    ELSE false 
                END AS flag_publication_sale_and_rent_same_month
            FROM
                fact_house_listing_flows AS lf 
            LEFT JOIN dim_date AS dd  
                ON dd.sk_date = lf.sk_first_listing_date
            LEFT JOIN dim_region AS dr 
                ON dr.sk_region = lf.sk_region
            LEFT JOIN datalake_ebdb_clean_prod.listing_business_context AS lbc 
                ON lbc.id_house = lf.sk_house_listing/1000
                AND lbc.business_context = 'RENT'
            LEFT JOIN lbc_sale AS sbc 
                ON sbc.id_house = lf.sk_house_listing/1000
            WHERE 
                lf.sk_first_listing_date > 0
                AND lf.sk_user_lead_affiliate > 0
                AND lf.mkt_origin = 'Doorman'
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
    ),
    base AS (
        SELECT
            dd.date,
            TO_CHAR(dd.week_start, 'yyyy-mm-dd') week_start,
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
        JOIN dim_date AS dd 
            ON dd.sk_date = iac.sk_date
        WHERE
            iac.cost IS NOT NULL
            AND dd.month_start >= date_trunc('month',CURRENT_DATE) - interval '24 month'
        GROUP BY 1,2,3,4,5,6,7,8,9,11
        HAVING costs>0
    )
    SELECT 
        date, 
        city_group,
        business_context,
        mkt_origin,
        SUM(costs) AS costs
    FROM base
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
        business_context = 'sale' OR (business_context IS NULL AND mkt_origin IN ('Doorman Sale','Indica Aí - Agents Sale','Indica Aí - General Sale'))
    GROUP BY 1, 2, 3, 4, 5, 6
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
        business_context = 'rent' OR (business_context IS NULL AND mkt_origin IN ('Doorman','Indica Aí - Agents','Indica Aí - General'))
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
    WHERE business_context = 'hybrid' 
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
    WHERE business_context = 'hybrid' 
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
        marketing.fact_marketing_daily_costs AS co
    JOIN dim_date AS dbt
        ON dbt.sk_date = co.sk_date
    WHERE
        co.funnel_side = 'supply'
        AND dbt.date BETWEEN '2020-01-01' AND CURRENT_DATE - 1
        AND co.mkt_origin IN ('Owner PWA','Price Calculator','New Channels')
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
        sum(replace(replace(nullif(bmc.cost,''),'$',''),',','')::float) AS costs
    FROM 
        datalake_raw.gsheets_offline_and_branding_marketing_costs AS bmc
        JOIN dim_date AS dbt
            ON bmc.sk_date::integer = dbt.sk_date
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
        datalake_marketing_costs_prod.offline_manual_costs AS c
        JOIN dim_date dd
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
        co.mkt_medium AS planning_mkt_level2,
        co.mkt_medium AS planning_mkt_level3,
        SUM(co.cost) AS costs
    FROM
        marketing.fact_marketing_daily_costs AS co
    JOIN dim_date AS dbt
        ON dbt.sk_date = co.sk_date
    WHERE co.funnel_side = 'demand'
        AND dbt.date BETWEEN '2019-01-01' AND CURRENT_DATE - 1
        AND co.mkt_medium != 'Social'
        AND co.mkt_origin = 'Tenants PWA - Sale'
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
        marketing.fact_marketing_daily_costs AS co
    JOIN dim_date dbt
        ON dbt.sk_date = co.sk_date
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
        marketing.fact_marketing_daily_costs AS co
    JOIN
        dim_date AS dbt ON dbt.sk_date = co.sk_date
    WHERE
        co.mkt_origin = 'CIQ'
    GROUP BY 1, 2, 3, 4, 5, 6
),
supply_ciq_cost_comission AS (
    SELECT
        data::DATE AS dt_cost,
        co.city AS city_group,
        'Rental' AS business,
        'Supply' AS planning_mkt_level1,
        'Affiliates' AS planning_mkt_level2,
        'CIQ' AS planning_mkt_level3,
        SUM(co.comission_cs_ciq_full::FLOAT + co.comission_cs_ciq_manager::FLOAT + co.comission_listing::FLOAT + co.impostos::FLOAT) AS costs
    FROM
        datalake_gsheets_clean_prod.ciq_costs AS co
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
)
SELECT 
    to_char(dt_cost,'YYYY-MM-DD') AS dt_cost, 
    to_char(date_trunc('week',dt_cost),'YYYY-MM-DD') AS week_start,
    to_char(date_trunc('month',dt_cost),'YYYY-MM-DD') AS month_start, 
    CASE
        WHEN date_part(mm,date_trunc('quarter',dt_cost)) = 4
            THEN 2  
         WHEN date_part(mm,date_trunc('quarter',dt_cost)) = 7
            THEN 3  
         WHEN date_part(mm,date_trunc('quarter',dt_cost)) = 10
            THEN 4 
         ELSE date_part(mm,date_trunc('quarter',dt_cost))
    END AS quarter,
    CASE
        WHEN date_part(mm,dt_cost) <= 6
            THEN 1
        ELSE 2
    END AS halfyear, 
    CASE
        WHEN cst.city_group IS NULL
            THEN 'Not Mapped'
        ELSE cst.city_group
    END AS city_group,
    dr.tier,
    cst.business,
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
        dim_region
    WHERE tier IS NOT NULL
) AS dr
    ON cst.city_group = dr.city_group
WHERE
    dt_cost < current_date 
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,13
ORDER BY 1 DESC, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
