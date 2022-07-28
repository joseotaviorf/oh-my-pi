WITH tp_status AS(
    SELECT DISTINCT
        dd.month_start,
        ts_start,
        city_group,
        sk_client,
        status,
        status_detail,
        ts_first_activation,
        city_group_first_activation,
        MAX(ts_start) OVER(PARTITION BY sk_client, city_group, month_start) AS last_status_start
    FROM
        dw_datamarts_growth_cross.tenant_prospect_status AS tps
        JOIN dw_public.dim_date AS dd
            ON dd.sk_date BETWEEN sk_start_date
                                  AND COALESCE(CAST(sk_end_date AS INT), CAST(date_format(current_date(), 'yyyyMMdd') as INT))
    WHERE
        dd.month_start >= DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '25 MONTH')
        AND ts_start >= ts_first_activation
),
monthly_tp_status AS(
    SELECT
        month_start,
        city_group,
        sk_client,
        city_group_first_activation,
        status AS status_month_end,
        status_detail AS status_detail_month_end,
        LAG(status) OVER(PARTITION BY sk_client, city_group ORDER BY month_start) AS status_month_start,
        LAG(status_detail) OVER(PARTITION BY sk_client, city_group ORDER BY month_start) AS status_detail_month_start
    FROM 
        tp_status
    WHERE
        ts_start = last_status_start
),
tps_monthly AS (
    SELECT DISTINCT
        month_start,
        city_group,
        CASE
            WHEN status_month_start = 'ACTIVE'
                THEN 'Active'
            WHEN (status_month_start IS NULL AND city_group_first_activation = city_group)
                OR (status_month_end = 'ACTIVE' AND status_detail_month_end = 'New TP')
                THEN 'New TP'
            WHEN status_month_start IS NULL
                OR (status_month_end = 'ACTIVE' AND status_detail_month_end = 'First activation in city_group')
                THEN 'First activation in city_group'
            WHEN status_month_start IN ('CHURNED', 'RENTED') AND status_month_end IN ('CHURNED', 'RENTED')
                THEN INITCAP(status_month_start)
            WHEN status_month_start IN ('CHURNED', 'RENTED')
                THEN 'Recovered'
        END AS status_month_start,
        CASE
            WHEN status_month_end = 'ACTIVE'
                THEN 'Active'
            WHEN status_month_end = 'CHURNED'
                THEN 'Churned'
            WHEN status_month_end = 'RENTED'
                THEN 'Rented'
        END AS status_month_end,
        sk_client
    FROM 
        monthly_tp_status
),
bp_status AS (
    SELECT DISTINCT
        dd.month_start,
        ts_start,
        city_group,
        sk_buyer,
        status,
        status_detail,
        ts_first_activation,
        city_group_first_activation,
        MAX(ts_start) OVER(PARTITION BY sk_buyer, city_group, month_start) AS last_status_start
    FROM
        dw_datamarts.buyer_prospect_status
        JOIN dw_public.dim_date AS dd
            ON dd.sk_date BETWEEN sk_start_date
                                  AND COALESCE(CAST(sk_end_date AS INT), CAST(date_format(current_date(), 'yyyyMMdd') as INT))
    WHERE
        dd.month_start >= DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '25 MONTH')
        AND ts_start >= ts_first_activation
),
monthly_bp_status as (
    SELECT
        month_start,
        city_group,
        sk_buyer,
        city_group_first_activation,
        status AS status_month_end,
        status_detail AS status_detail_month_end,
        LAG(status) OVER(partition by sk_buyer, city_group ORDER BY month_start) AS status_month_start,
        LAG(status_detail) OVER(partition by sk_buyer, city_group ORDER BY month_start) AS status_detail_month_start
    FROM 
        bp_status
    WHERE
        ts_start = last_status_start
),
bps_monthly AS (
    SELECT DISTINCT
        month_start,
        city_group,
        CASE
            WHEN status_month_start = 'ACTIVE'
                THEN 'Active'
            WHEN (status_month_start IS NULL AND city_group_first_activation = city_group)
                OR (status_month_end = 'ACTIVE' AND status_detail_month_end = 'New BP')
                THEN 'New BP'
            WHEN status_month_start IS NULL
                OR (status_month_end = 'ACTIVE' AND status_detail_month_end = 'First activation in city_group')
                THEN 'First activation in city_group'
            WHEN status_month_start = 'CHURNED' AND status_month_end = 'CHURNED'
                THEN INITCAP(status_month_start)
            WHEN status_month_start = 'SIGNED CCV' AND status_month_end = 'SIGNED CCV'
                THEN 'Signed CCV'
            WHEN status_month_start IN ('CHURNED', 'SIGNED CCV')
                THEN 'Recovered'
        END AS status_month_start,
        CASE
            WHEN status_month_end = 'ACTIVE'
                THEN 'Active'
            WHEN status_month_end = 'CHURNED'
                THEN 'Churned'
            WHEN status_month_end = 'SIGNED CCV'
                THEN 'Signed CCV'
        END AS status_month_end,
        sk_buyer
    FROM 
        monthly_bp_status
),
dim_house AS (
    SELECT
        id AS sk_house,
        id_region AS sk_region,
        CASE WHEN internal_admin_info LIKE '%[3P-%]%' THEN 'true' ELSE 'false' END AS is_3p
    FROM
        datalake_ebdb_clean.house
    GROUP BY 1,2,3
),
events AS (
    -------------------------
    -- Top of Funnel Users --
    -------------------------
    SELECT
        DATE_TRUNC('MONTH', ui.dt_event) AS month_start,
        city_group,
        CAST(NULL AS STRING) AS status_start,
        CAST(NULL AS STRING) AS status_end,
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
        CAST(NULL AS STRING) AS is_3p,
        COUNT(NULL) as marketing_cost,
        COUNT(NULL) as budget,
        COUNT(DISTINCT ui.id_tof_user) AS tof_users,
        COUNT(DISTINCT (CASE WHEN dh.is_3p = 'true' THEN ui.id_tof_user END)) AS tof_users_3p,
        COUNT(ui.id) AS tof_events,
        COUNT(CASE WHEN dh.is_3p = 'true' THEN ui.id END) AS tof_events_3p,
        COUNT(NULL) AS active_buyer_prospects,
        COUNT(NULL) AS ongoing_churned_buyer_prospects,
        COUNT(NULL) AS retained_buyer_prospects,
        COUNT(NULL) AS new_buyer_prospects,
        COUNT(NULL) AS buyer_prospects,
        COUNT(NULL) AS recovered_buyer_prospects,
        COUNT(NULL) AS buyer_prospect_churns,
        COUNT(NULL) AS buyer_prospect_deactivations_by_ccv,
        COUNT(NULL) AS sale_flows,
        COUNT(NULL) AS new_buyer_prospects_target,
        COUNT(NULL) AS recovered_buyer_prospects_target,
        COUNT(NULL) AS active_tenant_prospects,
        COUNT(NULL) AS ongoing_churned_tenant_prospects,
        COUNT(NULL) AS retained_tenant_prospects,
        COUNT(NULL) AS new_tenant_prospects,
        COUNT(NULL) AS tenant_prospects,
        COUNT(NULL) AS recovered_tenant_prospects,
        COUNT(NULL) AS tenant_prospect_churns,
        COUNT(NULL) AS tenant_prospect_deactivations_by_renting,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS new_tenant_prospects_target,
        COUNT(NULL) AS recovered_tenant_prospects_target,
        COUNT(NULL) AS tof_users_target
    FROM
        datalake_top_of_funnel_demand.user_interactions AS ui
    LEFT JOIN dw_public.dim_region AS dr
            ON CAST(ui.sk_region AS INT) = dr.sk_region
    LEFT JOIN dim_house AS dh
            ON ui.id_house = dh.sk_house
    WHERE
        ui.dt_event >= DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '24 MONTH')
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    UNION ALL
    ----------------------------
    -- Buyer Prospects Stocks --
    ----------------------------
    SELECT
        month_start,
        city_group,
        status_month_start,
        CASE WHEN month_start = DATE_TRUNC('MONTH', CURRENT_DATE) THEN '' ELSE status_month_end END AS status_month_end,
        CAST(NULL AS STRING) AS business_context,
        CAST(NULL AS STRING) AS campaign_context,
        CAST(NULL AS STRING) AS mkt_origin,
        CAST(NULL AS STRING) AS mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS is_3p,
        COUNT(NULL) as marketing_cost,
        COUNT(NULL) as budget,
        COUNT(NULL) AS tof_users,
        COUNT(NULL) AS tof_users_3p,
        COUNT(NULL) AS tof_events,
        COUNT(NULL) AS tof_events_3p,
        COUNT(DISTINCT CASE WHEN status_month_end = 'Active' THEN sk_buyer ELSE NULL END) AS active_buyer_prospects,
        COUNT(DISTINCT CASE WHEN status_month_end = 'Churned' THEN sk_buyer ELSE NULL END) AS ongoing_churned_buyer_prospects,
        COUNT(DISTINCT CASE WHEN status_month_start = 'Active' AND status_month_end != 'Churned' THEN sk_buyer ELSE NULL END) AS retained_buyer_prospects,
        COUNT(NULL) AS new_buyer_prospects,
        COUNT(NULL) AS buyer_prospects,
        COUNT(NULL) AS recovered_buyer_prospects,
        COUNT(NULL) AS buyer_prospect_churns,
        COUNT(NULL) AS buyer_prospect_deactivations_by_ccv,
        COUNT(NULL) AS sale_flows,
        COUNT(NULL) AS new_buyer_prospects_target,
        COUNT(NULL) AS recovered_buyer_prospects_target,
        COUNT(NULL) AS active_tenant_prospects,
        COUNT(NULL) AS ongoing_churned_tenant_prospects,
        COUNT(NULL) AS retained_tenant_prospects,
        COUNT(NULL) AS new_tenant_prospects,
        COUNT(NULL) AS tenant_prospects,
        COUNT(NULL) AS recovered_tenant_prospects,
        COUNT(NULL) AS tenant_prospect_churns,
        COUNT(NULL) AS tenant_prospect_deactivations_by_renting,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS new_tenant_prospects_target,
        COUNT(NULL) AS recovered_tenant_prospects_target,
        COUNT(NULL) AS tof_users_target
    FROM
        bps_monthly
    WHERE
        month_start >= DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '24 MONTH')
        AND month_start < DATE_TRUNC('MONTH', CURRENT_DATE)
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    UNION ALL
    -------------------------------------
    -- Sale Metrics, targets and costs --
    -------------------------------------
    SELECT
        DATE(DATE_TRUNC('MONTH', pmmd.dt_event)) AS month_start,
        pmmd.city_group,
        CASE
            WHEN pmmd.sk_buyer IS NOT NULL
                THEN status_month_start
        END AS status_month_start,
        CASE
            WHEN DATE_TRUNC('MONTH', pmmd.dt_event) = DATE_TRUNC('month', CURRENT_DATE)
                THEN ''
            WHEN pmmd.sk_buyer IS NOT NULL
                THEN bps.status_month_end
        END AS status_month_end,
        'sale' AS business_context,
        pmmd.campaign_context,
        pmmd.mkt_origin,
        pmmd.mkt_channel,
        pmmd.mkt_medium,
        pmmd.mkt_source,
        pmmd.is_3p,
        SUM(pmmd.marketing_cost) as marketing_cost,
        SUM(pmmd.budget) as budget,
        COUNT(NULL) AS tof_users,
        COUNT(NULL) AS tof_users_3p,
        COUNT(NULL) AS tof_events,
        COUNT(NULL) AS tof_events_3p,
        COUNT(NULL) AS active_buyer_prospects,
        COUNT(NULL) AS ongoing_churned_buyer_prospects,
        COUNT(NULL) AS retained_buyer_prospects,
        COUNT(DISTINCT CASE WHEN pmmd.buyer_prospect_order = 1 THEN pmmd.sk_buyer ELSE NULL END) AS new_buyer_prospects,
        COUNT(DISTINCT CASE WHEN pmmd.status = 'ACTIVE' THEN pmmd.sk_buyer ELSE NULL END) AS buyer_prospects,
        COUNT(DISTINCT CASE WHEN pmmd.status_detail ilike 'Recover%' AND pmmd.ts_event = pmmd.ts_status_start THEN pmmd.sk_buyer ELSE NULL END) AS recovered_buyer_prospects,
        COUNT(DISTINCT CASE WHEN pmmd.status = 'CHURNED' THEN pmmd.sk_buyer ELSE NULL END) AS buyer_prospect_churns,
        COUNT(DISTINCT CASE WHEN pmmd.status = 'SIGNED CCV' THEN pmmd.sk_buyer ELSE NULL END) AS buyer_prospect_deactivations_by_ccv,
        COUNT(DISTINCT pmmd.sk_sale_flow) AS sale_flows,
        SUM(pmmd.new_buyer_prospects_target) AS new_buyer_prospects_target,
        SUM(pmmd.recovered_buyer_prospects_target) AS recovered_buyer_prospects_target,
        COUNT(NULL) AS active_tenant_prospects,
        COUNT(NULL) AS ongoing_churned_tenant_prospects,
        COUNT(NULL) AS retained_tenant_prospects,
        COUNT(NULL) AS new_tenant_prospects,
        COUNT(NULL) AS tenant_prospects,
        COUNT(NULL) AS recovered_tenant_prospects,
        COUNT(NULL) AS tenant_prospect_churns,
        COUNT(NULL) AS tenant_prospect_deactivations_by_renting,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS new_tenant_prospects_target,
        COUNT(NULL) AS recovered_tenant_prospects_target,
        COUNT(NULL) AS tof_users_target
    FROM
        dw_datamarts_growth_cross.sale_performance_marketing_metrics_demand AS pmmd
    LEFT JOIN 
        bps_monthly AS bps
            ON bps.sk_buyer = pmmd.sk_buyer
                AND bps.city_group = pmmd.city_group
                AND bps.month_start = DATE_TRUNC('MONTH', pmmd.dt_event)
    WHERE
        dt_event >= DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '24 MONTH')
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    UNION ALL
    -----------------------------
    -- Tenant Prospects Stocks --
    -----------------------------
    SELECT
        month_start,
        city_group,
        status_month_start,
        CASE WHEN month_start = DATE_TRUNC('MONTH', CURRENT_DATE) THEN '' ELSE status_month_end END AS status_month_end,
        CAST(NULL AS STRING) AS business_context,
        CAST(NULL AS STRING) AS campaign_context,
        CAST(NULL AS STRING) AS mkt_origin,
        CAST(NULL AS STRING) AS mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CAST(NULL AS STRING) AS is_3p,
        COUNT(NULL) AS marketing_cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS tof_users,
        COUNT(NULL) AS tof_users_3p,
        COUNT(NULL) AS tof_events,
        COUNT(NULL) AS tof_events_3p,
        COUNT(NULL) AS active_buyer_prospects,
        COUNT(NULL) AS ongoing_churned_buyer_prospects,
        COUNT(NULL) AS retained_buyer_prospects,
        COUNT(NULL) AS new_buyer_prospects,
        COUNT(NULL) AS buyer_prospects,
        COUNT(NULL) AS recovered_buyer_prospects,
        COUNT(NULL) AS buyer_prospect_churns,
        COUNT(NULL) AS buyer_prospect_deactivations_by_ccv,
        COUNT(NULL) AS sale_flows,
        COUNT(NULL) AS new_buyer_prospects_target,
        COUNT(NULL) AS recovered_buyer_prospects_target,
        COUNT(DISTINCT CASE WHEN tps.status_month_end = 'Active' THEN tps.sk_client ELSE NULL END) AS active_tenant_prospects,
        COUNT(DISTINCT CASE WHEN tps.status_month_end = 'Churned' THEN tps.sk_client ELSE NULL END) AS ongoing_churned_tenant_prospects,
        COUNT(DISTINCT CASE WHEN tps.status_month_start = 'Active' AND tps.status_month_end != 'Churned' THEN tps.sk_client ELSE NULL END) AS retained_tenant_prospects,
        COUNT(NULL) AS new_tenant_prospects,
        COUNT(NULL) AS tenant_prospects,
        COUNT(NULL) AS recovered_tenant_prospects,
        COUNT(NULL) AS tenant_prospect_churns,
        COUNT(NULL) AS tenant_prospect_deactivations_by_renting,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS new_tenant_prospects_target,
        COUNT(NULL) AS recovered_tenant_prospects_target,
        COUNT(NULL) AS tof_users_target
    FROM
        tps_monthly AS tps
    WHERE
        month_start >= DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '24 MONTH')
        AND month_start < DATE_TRUNC('MONTH', CURRENT_DATE)
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    UNION ALL
    -------------------------------------
    -- Rent Metrics, targets and costs --
    -------------------------------------
    SELECT
        DATE(DATE_TRUNC('MONTH', pmmd.dt_event)) AS month_start,
        pmmd.city_group,
        CASE
            WHEN pmmd.sk_client IS NOT NULL
                THEN status_month_start
        END AS status_month_start,
        CASE
            WHEN DATE_TRUNC('MONTH', pmmd.dt_event) = DATE_TRUNC('MONTH', CURRENT_DATE)
                THEN ''
            WHEN pmmd.sk_client IS NOT NULL
                THEN tps.status_month_end
        END AS status_month_end,
        'rent' AS business_context,
        'Rental' AS campaign_context,
        pmmd.mkt_origin,
        pmmd.mkt_channel,
        pmmd.mkt_medium,
        pmmd.mkt_source,
        CAST(NULL AS STRING) AS is_3p,
        SUM(pmmd.marketing_cost) AS marketing_cost,
        SUM(pmmd.budget) AS budget,
        COUNT(NULL) AS tof_users,
        COUNT(NULL) AS tof_users_3p,
        COUNT(NULL) AS tof_events,
        COUNT(NULL) AS tof_events_3p,
        COUNT(NULL) AS active_buyer_prospects,
        COUNT(NULL) AS ongoing_churned_buyer_prospects,
        COUNT(NULL) AS retained_buyer_prospects,
        COUNT(NULL) AS new_buyer_prospects,
        COUNT(NULL) AS buyer_prospects,
        COUNT(NULL) AS recovered_buyer_prospects,
        COUNT(NULL) AS buyer_prospect_churns,
        COUNT(NULL) AS buyer_prospect_deactivations_by_ccv,
        COUNT(NULL) AS sale_flows,
        COUNT(NULL) AS new_buyer_prospects_target,
        COUNT(NULL) AS recovered_buyer_prospects_target,
        COUNT(NULL) AS active_tenant_prospects,
        COUNT(NULL) AS ongoing_churned_tenant_prospects,
        COUNT(NULL) AS retained_tenant_prospects,
        COUNT(DISTINCT CASE WHEN pmmd.tenant_prospect_order = 1 THEN pmmd.sk_client ELSE NULL END) AS new_tenant_prospects,
        COUNT(DISTINCT CASE WHEN pmmd.status = 'ACTIVE' THEN pmmd.sk_client ELSE NULL END) AS tenant_prospects,
        COUNT(DISTINCT CASE WHEN pmmd.status_detail ilike 'Recover%' AND pmmd.ts_event = pmmd.ts_status_start THEN pmmd.sk_client ELSE NULL END) AS recovered_tenant_prospects,
        COUNT(DISTINCT CASE WHEN pmmd.status = 'CHURNED' THEN pmmd.sk_client ELSE NULL END) AS tenant_prospect_churns,
        COUNT(DISTINCT CASE WHEN pmmd.status = 'RENTED' THEN pmmd.sk_client ELSE NULL END) AS tenant_prospect_deactivations_by_renting,
        COUNT(DISTINCT pmmd.sk_rf) AS rent_flows,
        SUM(pmmd.new_tenant_prospects_target) AS new_tenant_prospects_target,
        SUM(pmmd.recovered_tenant_prospects_target) AS recovered_tenant_prospects_target,
        COUNT(NULL) AS tof_users_target
    FROM
        dw_datamarts_growth_cross.performance_marketing_metrics_demand AS pmmd
    LEFT JOIN 
        tps_monthly AS tps
            ON tps.sk_client = pmmd.sk_client
                AND tps.city_group = pmmd.city_group
                AND tps.month_start = DATE_TRUNC('MONTH', pmmd.dt_event)
    WHERE
        DATE_TRUNC('MONTH', pmmd.dt_event) >= DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '24 MONTH')
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    UNION ALL
    ------------------------
    -- ToF Rental Targets --
    ------------------------
    SELECT
        CAST(dt_month_started AS DATE) AS month_start,
        city_group,
        CAST(NULL AS STRING) AS status_start,
        CAST(NULL AS STRING) AS status_end,
        'rent' AS business_context,
        'Rental' AS campaign_context,
        'Tenants PWA' AS mkt_origin,
        CASE mkt_channel
            WHEN 'Paid' THEN 'Paid Acquisition'
            ELSE mkt_channel
        END AS mkt_channel,
        mkt_medium,
        mkt_source,
        CAST(NULL AS STRING) AS is_3p,
        COUNT(NULL) AS marketing_cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS tof_users,
        COUNT(NULL) AS tof_users_3p,
        COUNT(NULL) AS tof_events,
        COUNT(NULL) AS tof_events_3p,
        COUNT(NULL) AS active_buyer_prospects,
        COUNT(NULL) AS ongoing_churned_buyer_prospects,
        COUNT(NULL) AS retained_buyer_prospects,
        COUNT(NULL) AS new_buyer_prospects,
        COUNT(NULL) AS buyer_prospects,
        COUNT(NULL) AS recovered_buyer_prospects,
        COUNT(NULL) AS buyer_prospect_churns,
        COUNT(NULL) AS buyer_prospect_deactivations_by_ccv,
        COUNT(NULL) AS sale_flows,
        COUNT(NULL) AS new_buyer_prospects_target,
        COUNT(NULL) AS recovered_buyer_prospects_target,
        COUNT(NULL) AS active_tenant_prospects,
        COUNT(NULL) AS ongoing_churned_tenant_prospects,
        COUNT(NULL) AS retained_tenant_prospects,
        COUNT(NULL) AS new_tenant_prospects,
        COUNT(NULL) AS tenant_prospects,
        COUNT(NULL) AS recovered_tenant_prospects,
        COUNT(NULL) AS tenant_prospect_churns,
        COUNT(NULL) AS tenant_prospect_deactivations_by_renting,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS new_tenant_prospects_target,
        COUNT(NULL) AS recovered_tenant_prospects_target,
        SUM(CAST(tof_users_target AS FLOAT)) AS tof_users_target
    FROM
        datalake_gsheets_clean.rental_tof_monthly_targets
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
    UNION ALL
    ----------------------
    -- ToF Sale Targets --
    ----------------------
    SELECT
        CAST(month_start AS DATE) AS month_start,
        city_group,
        CAST(NULL AS STRING) AS status_start,
        CAST(NULL AS STRING) AS status_end,
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
        CAST(NULL AS STRING) AS is_3p,
        COUNT(NULL) as marketing_cost,
        COUNT(NULL) as budget,
        COUNT(NULL) AS tof_users,
        COUNT(NULL) AS tof_users_3p,
        COUNT(NULL) AS tof_events,
        COUNT(NULL) AS tof_events_3p,
        COUNT(NULL) AS active_buyer_prospects,
        COUNT(NULL) AS ongoing_churned_buyer_prospects,
        COUNT(NULL) AS retained_buyer_prospects,
        COUNT(NULL) AS new_buyer_prospects,
        COUNT(NULL) AS buyer_prospects,
        COUNT(NULL) AS recovered_buyer_prospects,
        COUNT(NULL) AS buyer_prospect_churns,
        COUNT(NULL) AS buyer_prospect_deactivations_by_ccv,
        COUNT(NULL) AS sale_flows,
        COUNT(NULL) AS new_buyer_prospects_target,
        COUNT(NULL) AS recovered_buyer_prospects_target,
        COUNT(NULL) AS active_tenant_prospects,
        COUNT(NULL) AS ongoing_churned_tenant_prospects,
        COUNT(NULL) AS retained_tenant_prospects,
        COUNT(NULL) AS new_tenant_prospects,
        COUNT(NULL) AS tenant_prospects,
        COUNT(NULL) AS recovered_tenant_prospects,
        COUNT(NULL) AS tenant_prospect_churns,
        COUNT(NULL) AS tenant_prospect_deactivations_by_renting,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS new_tenant_prospects_target,
        COUNT(NULL) AS recovered_tenant_prospects_target,
        SUM(CAST(tof_users_target AS FLOAT)) AS tof_users_target
    FROM
        datalake_gsheets_clean.sale_tof_monthly_targets
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
)
SELECT
    ROW_NUMBER() OVER(ORDER BY month_start) AS pkey,
    COALESCE(city_group, 'Not Mapped') AS city_group,
    status_start AS status_month_start,
    status_end AS status_month_end,
    business_context,
    campaign_context,
    mkt_origin,
    CASE mkt_channel
        WHEN 'Paid' THEN 'Paid Acquisition'
        ELSE mkt_channel
    END as mkt_channel,
    mkt_medium,
    mkt_source,
    month_start,
    is_3p,
    SUM(marketing_cost) as marketing_cost,
    SUM(budget) as budget,
    SUM(tof_users) AS tof_users,
    SUM(tof_users_3p) AS tof_users_3p,
    SUM(tof_events) AS tof_events,
    SUM(tof_events_3p) AS tof_events_3p,
    SUM(active_buyer_prospects) AS active_buyer_prospects,
    SUM(ongoing_churned_buyer_prospects) AS ongoing_churned_buyer_prospects,
    SUM(retained_buyer_prospects) AS retained_buyer_prospects,
    SUM(new_buyer_prospects) AS new_buyer_prospects,
    SUM(buyer_prospects) AS buyer_prospects,
    SUM(recovered_buyer_prospects) AS recovered_buyer_prospects,
    SUM(buyer_prospect_churns) AS buyer_prospect_churns,
    SUM(buyer_prospect_deactivations_by_ccv) AS buyer_prospect_deactivations_by_ccv,
    SUM(sale_flows) AS sale_flows,
    SUM(new_buyer_prospects_target) AS new_buyer_prospects_target,
    SUM(recovered_buyer_prospects_target) AS recovered_buyer_prospects_target,
    SUM(active_tenant_prospects) AS active_tenant_prospects,
    SUM(ongoing_churned_tenant_prospects) AS ongoing_churned_tenant_prospects,
    SUM(retained_tenant_prospects) AS retained_tenant_prospects,
    SUM(new_tenant_prospects) AS new_tenant_prospects,
    SUM(tenant_prospects) AS tenant_prospects,
    SUM(recovered_tenant_prospects) AS recovered_tenant_prospects,
    SUM(tenant_prospect_churns) AS tenant_prospect_churns,
    SUM(tenant_prospect_deactivations_by_renting) AS tenant_prospect_deactivations_by_renting,
    SUM(rent_flows) AS rent_flows,
    SUM(new_tenant_prospects_target) AS new_tenant_prospects_target,
    SUM(recovered_tenant_prospects_target) AS recovered_tenant_prospects_target,
    SUM(tof_users_target) AS tof_users_target
FROM
    events
GROUP BY 2,3,4,5,6,7,8,9,10,11,12