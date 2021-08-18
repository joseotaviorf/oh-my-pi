    WITH
    events AS (
        SELECT
            ui.dt_event,
            city_group,
            LOWER(ui.business_context) AS business_context,
            CASE
                WHEN LOWER(ui.business_context) = 'sale'
                    AND (LOWER(utm_campaign) LIKE '%sale%'
                        OR LOWER(utm_campaign) LIKE '%girafa%'
                        OR LOWER(utm_campaign) LIKE '%vender%'
                        OR LOWER(utm_campaign) = 'whatsapp_s')
                    THEN 'Sale'
                WHEN LOWER(ui.business_context) = 'sale'
                    AND (NULLIF(utm_campaign, '') IS NULL
                        OR LOWER(utm_campaign) LIKE '%branded%')
                    THEN 'Organic'
                ELSE 'Rental'
            END AS campaign_context,
            ui.mkt_origin,
            ui.mkt_channel,
            ui.mkt_medium,
            ui.mkt_source,
            COUNT(NULL) as marketing_cost,
            COUNT(NULL) as budget,
            COUNT(DISTINCT ui.id_tof_user) AS tof_users,
            COUNT(NULL) AS new_buyer_prospects,
            COUNT(NULL) AS buyer_prospects,
            COUNT(NULL) AS sale_flows,
            COUNT(NULL) AS new_buyer_prospects_target,
            COUNT(NULL) AS new_tenant_prospects,
            COUNT(NULL) AS tenant_prospects,
            COUNT(NULL) AS rent_flows,
            COUNT(NULL) AS new_tenant_prospects_target,
            COUNT(NULL) AS tof_users_target
        FROM
            datalake_top_of_funnel_demand_prod.user_interactions AS ui
            LEFT JOIN dim_region AS dr
                ON ui.sk_region::INT = dr.sk_region
        WHERE
            ui.dt_event >= CURRENT_DATE - INTERVAL '365 DAY'
        GROUP BY 1,2,3,4,5,6,7,8

        UNION ALL

        SELECT
            dt_event,
            city_group,
            'sale' AS business_context,
            campaign_context,
            pmmd.mkt_origin,
            pmmd.mkt_channel,
            pmmd.mkt_medium,
            pmmd.mkt_source,
            SUM(marketing_cost) as marketing_cost,
            SUM(budget) as budget,
            COUNT(NULL) AS tof_users,
            COUNT(DISTINCT CASE WHEN buyer_prospect_order = 1 THEN sk_buyer ELSE NULL END) AS new_buyer_prospects,
            COUNT(DISTINCT sk_buyer) AS buyer_prospects,
            COUNT(DISTINCT sk_sale_flow) AS sale_flows,
            SUM(new_buyer_prospects_target) AS new_buyer_prospects_target,
            COUNT(NULL) AS new_tenant_prospects,
            COUNT(NULL) AS tenant_prospects,
            COUNT(NULL) AS rent_flows,
            COUNT(NULL) AS new_tenant_prospects_target,
            COUNT(NULL) AS tof_users_target
        FROM
            datamarts.sale_performance_marketing_metrics_demand AS pmmd
        WHERE
            dt_event >= CURRENT_DATE - INTERVAL '365 DAY'
        GROUP BY 1,2,3,4,5,6,7,8

        UNION ALL

        SELECT
            dt_event,
            city_group,
            'rent' AS business_context,
            'Rental' AS campaign_context,
            pmmd.mkt_origin,
            pmmd.mkt_channel,
            pmmd.mkt_medium,
            pmmd.mkt_source,
            SUM(marketing_cost) as marketing_cost,
            SUM(budget) as budget,
            COUNT(NULL) AS tof_users,
            COUNT(NULL) AS new_buyer_prospects,
            COUNT(NULL) AS buyer_prospects,
            COUNT(NULL) AS sale_flows,
            COUNT(NULL) AS new_buyer_prospects_target,
            COUNT(DISTINCT CASE WHEN tenant_prospect_order = 1 THEN sk_client ELSE NULL END) AS new_tenant_prospects,
            COUNT(DISTINCT sk_client) AS tenant_prospects,
            COUNT(DISTINCT sk_rf) AS rent_flows,
            SUM(new_tenant_prospects_target) AS new_tenant_prospects_target,
            COUNT(NULL) AS tof_users_target
        FROM
            datamarts.performance_marketing_metrics_demand AS pmmd
        WHERE
            dt_event >= CURRENT_DATE - INTERVAL '365 DAY'
        GROUP BY 1,2,3,4,5,6,7,8

        UNION ALL

        SELECT
            date::DATE AS dt_event,
            city_group,
            'rent' AS business_context,
            'Rental' AS campaign_context,
            'Tenants PWA' AS mkt_origin,
            CASE mkt_channel
                WHEN 'Paid' THEN 'Paid Acquisition'
                ELSE mkt_channel
            END as mkt_channel,
            mkt_medium,
            mkt_source,
            COUNT(NULL) as marketing_cost,
            COUNT(NULL) as budget,
            COUNT(NULL) AS tof_users,
            COUNT(NULL) AS new_buyer_prospects,
            COUNT(NULL) AS buyer_prospects,
            COUNT(NULL) AS sale_flows,
            COUNT(NULL) AS new_buyer_prospects_target,
            COUNT(NULL) AS new_tenant_prospects,
            COUNT(NULL) AS tenant_prospects,
            COUNT(NULL) AS rent_flows,
            COUNT(NULL) AS new_tenant_prospects_target,
            SUM(daily_tof_target::FLOAT) AS tof_users_target
        FROM
            datalake_gsheets_clean_prod.rental_tof_daily_targets
        GROUP BY 1,2,3,4,5,6,7,8

        UNION ALL

        SELECT
            date::DATE AS dt_event,
            city AS city_group,
            'sale' AS business_context,
            CASE
                WHEN context = 'Rent' OR mkt_channel = 'For Rent'
                    THEN 'Rental'
                WHEN COALESCE(NULLIF(context, ''), '-') != '-'
                    THEN context
                WHEN mkt_channel IN ('Organic', 'Other')
                    THEN 'Organic'
                ELSE 'Sale'
            END AS campaign_context,
            'Tenants PWA' AS mkt_origin,
            CASE mkt_channel
                WHEN 'Paid' THEN 'Paid Acquisition'
                ELSE mkt_channel
            END as mkt_channel,
            mkt_medium,
            mkt_source,
            COUNT(NULL) as marketing_cost,
            COUNT(NULL) as budget,
            COUNT(NULL) AS tof_users,
            COUNT(NULL) AS new_buyer_prospects,
            COUNT(NULL) AS buyer_prospects,
            COUNT(NULL) AS sale_flows,
            COUNT(NULL) AS new_buyer_prospects_target,
            COUNT(NULL) AS new_tenant_prospects,
            COUNT(NULL) AS tenant_prospects,
            COUNT(NULL) AS rent_flows,
            COUNT(NULL) AS new_tenant_prospects_target,
            SUM(tof_users_target::FLOAT) AS tof_users_target
        FROM
            datalake_gsheets_clean_prod.sale_tof_daily_targets
        GROUP BY 1,2,3,4,5,6,7,8
    )
    SELECT
        ROW_NUMBER() OVER() AS pkey,
        COALESCE(city_group, 'Not Mapped') AS city_group,
        business_context,
        campaign_context,
        mkt_origin,
        CASE mkt_channel
            WHEN 'Paid' THEN 'Paid Acquisition'
            ELSE mkt_channel
        END as mkt_channel,
        mkt_medium,
        mkt_source,
        dt_event,
        SUM(marketing_cost) as marketing_cost,
        SUM(budget) as budget,
        SUM(tof_users) AS tof_users,
        SUM(new_buyer_prospects) AS new_buyer_prospects,
        SUM(buyer_prospects) AS buyer_prospects,
        SUM(sale_flows) AS sale_flows,
        SUM(new_buyer_prospects_target) AS new_buyer_prospects_target,
        SUM(new_tenant_prospects) AS new_tenant_prospects,
        SUM(tenant_prospects) AS tenant_prospects,
        SUM(rent_flows) AS rent_flows,
        SUM(new_tenant_prospects_target) AS new_tenant_prospects_target,
        SUM(tof_users_target) AS tof_users_target
    FROM
        events
    GROUP BY 2,3,4,5,6,7,8,9