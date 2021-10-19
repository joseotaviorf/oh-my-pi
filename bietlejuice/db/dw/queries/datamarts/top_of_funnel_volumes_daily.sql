WITH
tp_status AS (
    SELECT DISTINCT
        dd.date,
        ts_start,
        city_group,
        sk_client,
        status,
        status_detail,
        ts_first_activation,
        city_group_first_activation,
        MAX(ts_start) OVER(PARTITION BY sk_client, city_group, date) AS last_status_start
    FROM
        datamarts.tenant_prospect_status AS tps
        JOIN dim_date AS dd
            ON dd.sk_date BETWEEN sk_start_date
                                  AND COALESCE(sk_end_date::INT, TO_CHAR(CURRENT_DATE, 'YYYYMMDD')::INT)
    WHERE
        dd.date >= CURRENT_DATE - INTERVAL '721 DAY'
        AND ts_start >= ts_first_activation
),
daily_tp_status as (
    select
        date,
        city_group,
        sk_client,
        city_group_first_activation,
        status AS status_date_end,
        status_detail AS status_detail_date_end,
        lag(status) over(partition by sk_client, city_group order by date) as status_date_start,
        lag(status_detail) over(partition by sk_client, city_group order by date) as status_detail_date_start
    from tp_status
    where
        ts_start = last_status_start
),
tps_daily AS (
    select distinct
        date,
        city_group,
        CASE
            WHEN status_date_start = 'ACTIVE'
                THEN 'Active'
            WHEN (status_date_start IS NULL AND city_group_first_activation = city_group)
                OR (status_date_end = 'ACTIVE' AND status_detail_date_end = 'New TP')
                THEN 'New TP'
            WHEN status_date_start IS NULL
                OR (status_date_end = 'ACTIVE' AND status_detail_date_end = 'First activation in city_group')
                THEN 'First activation in city_group'
            WHEN status_date_start IN ('CHURNED', 'RENTED') AND status_date_end IN ('CHURNED', 'RENTED')
                THEN INITCAP(status_date_start)
            WHEN status_date_start IN ('CHURNED', 'RENTED')
                THEN 'Recovered'
        END AS status_date_start,
        CASE
            WHEN status_date_end = 'ACTIVE'
                THEN 'Active'
            WHEN status_date_end = 'CHURNED'
                THEN 'Churned'
            WHEN status_date_end = 'RENTED'
                THEN 'Rented'
        END AS status_date_end,
        sk_client
    from daily_tp_status
),
bp_status AS (
    SELECT DISTINCT
        dd.date,
        ts_start,
        city_group,
        sk_buyer,
        status,
        status_detail,
        ts_first_activation,
        city_group_first_activation,
        MAX(ts_start) OVER(PARTITION BY sk_buyer, city_group, date) AS last_status_start
    FROM
        datamarts.buyer_prospect_status
        JOIN dim_date AS dd
            ON dd.sk_date BETWEEN sk_start_date
                                  AND COALESCE(sk_end_date::INT, TO_CHAR(CURRENT_DATE, 'YYYYMMDD')::INT)
    WHERE
        dd.date >= CURRENT_DATE - INTERVAL '721 DAY'
        AND ts_start >= ts_first_activation
),
daily_bp_status as (
    select
        date,
        city_group,
        sk_buyer,
        city_group_first_activation,
        status AS status_date_end,
        status_detail AS status_detail_date_end,
        lag(status) over(partition by sk_buyer, city_group order by date) as status_date_start,
        lag(status_detail) over(partition by sk_buyer, city_group order by date) as status_detail_date_start
    from bp_status
    where
        ts_start = last_status_start
),
bps_daily AS (
    select distinct
        date,
        city_group,
        CASE
            WHEN status_date_start = 'ACTIVE'
                THEN 'Active'
            WHEN (status_date_start IS NULL AND city_group_first_activation = city_group)
                OR (status_date_end = 'ACTIVE' AND status_detail_date_end = 'New BP')
                THEN 'New BP'
            WHEN status_date_start IS NULL
                OR (status_date_end = 'ACTIVE' AND status_detail_date_end = 'First activation in city_group')
                THEN 'First activation in city_group'
            WHEN status_date_start = 'CHURNED' AND status_date_end = 'CHURNED'
                THEN INITCAP(status_date_start)
            WHEN status_date_start = 'SIGNED CCV' AND status_date_end = 'SIGNED CCV'
                THEN 'Signed CCV'
            WHEN status_date_start IN ('CHURNED', 'SIGNED CCV')
                THEN 'Recovered'
        END AS status_date_start,
        CASE
            WHEN status_date_end = 'ACTIVE'
                THEN 'Active'
            WHEN status_date_end = 'CHURNED'
                THEN 'Churned'
            WHEN status_date_end = 'SIGNED CCV'
                THEN 'Signed CCV'
        END AS status_date_end,
        sk_buyer
    from daily_bp_status
),
events AS (
    -------------------------
    -- Top of Funnel Users --
    -------------------------
    SELECT
        ui.dt_event,
        city_group,
        NULL::TEXT AS status_start,
        NULL::TEXT AS status_end,
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
        COUNT(NULL) AS tof_users_target
    FROM
        datalake_top_of_funnel_demand_prod.user_interactions AS ui
        LEFT JOIN dim_region AS dr
            ON ui.sk_region::INT = dr.sk_region
    WHERE
        ui.dt_event >= CURRENT_DATE - INTERVAL '720 DAY'
    GROUP BY 1,2,3,4,5,6,7,8,9,10
    UNION ALL
    ----------------------------
    -- Buyer Prospects Stocks --
    ----------------------------
    SELECT
        date AS dt_event,
        city_group,
        status_date_start,
        CASE WHEN date = CURRENT_DATE THEN '' ELSE status_date_end END AS status_date_end,
        NULL::TEXT AS business_context,
        NULL::TEXT AS campaign_context,
        NULL::TEXT AS mkt_origin,
        NULL::TEXT AS mkt_channel,
        NULL::TEXT AS mkt_medium,
        NULL::TEXT AS mkt_source,
        COUNT(NULL) as marketing_cost,
        COUNT(NULL) as budget,
        COUNT(NULL) AS tof_users,
        COUNT(DISTINCT CASE WHEN status_date_end = 'Active' THEN sk_buyer ELSE NULL END) AS active_buyer_prospects,
        COUNT(DISTINCT CASE WHEN status_date_end = 'Churned' THEN sk_buyer ELSE NULL END) AS ongoing_churned_buyer_prospects,
        COUNT(DISTINCT CASE WHEN status_date_start = 'Active' AND status_date_end != 'Churned' THEN sk_buyer ELSE NULL END) AS retained_buyer_prospects,
        COUNT(NULL) AS new_buyer_prospects,
        COUNT(NULL) AS buyer_prospects,
        COUNT(NULL) AS recovered_buyer_prospects,
        COUNT(NULL) AS buyer_prospect_churns,
        COUNT(NULL) AS buyer_prospect_deactivations_by_ccv,
        COUNT(NULL) AS sale_flows,
        COUNT(NULL) AS new_buyer_prospects_target,
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
        COUNT(NULL) AS tof_users_target
    FROM
        bps_daily
    WHERE
        date >= CURRENT_DATE - INTERVAL '720 DAY'
        AND date < CURRENT_DATE
    GROUP BY 1,2,3,4,5,6,7,8,9,10
    UNION ALL
    -------------------------------------
    -- Sale Metrics, targets and costs --
    -------------------------------------
    SELECT
        pmmd.dt_event,
        pmmd.city_group,
        CASE
            WHEN pmmd.sk_buyer IS NOT NULL
                THEN status_date_start
        END AS status_date_start,
        CASE
            WHEN pmmd.dt_event = CURRENT_DATE
                THEN ''
            WHEN pmmd.sk_buyer IS NOT NULL
                THEN bps.status_date_end
        END AS status_date_end,
        'sale' AS business_context,
        pmmd.campaign_context,
        pmmd.mkt_origin,
        pmmd.mkt_channel,
        pmmd.mkt_medium,
        pmmd.mkt_source,
        SUM(pmmd.marketing_cost) as marketing_cost,
        SUM(pmmd.budget) as budget,
        COUNT(NULL) AS tof_users,
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
        COUNT(NULL) AS tof_users_target
    FROM
        datamarts.sale_performance_marketing_metrics_demand AS pmmd
        LEFT JOIN bps_daily AS bps
            ON bps.sk_buyer = pmmd.sk_buyer
            AND bps.city_group = pmmd.city_group
            AND bps.date = pmmd.dt_event
    WHERE
        dt_event >= CURRENT_DATE - INTERVAL '720 DAY'
    GROUP BY 1,2,3,4,5,6,7,8,9,10
    UNION ALL
    -----------------------------
    -- Tenant Prospects Stocks --
    -----------------------------
    SELECT
        date AS dt_event,
        city_group,
        status_date_start,
        CASE WHEN date = CURRENT_DATE THEN '' ELSE status_date_end END AS status_date_end,
        NULL::TEXT AS business_context,
        NULL::TEXT AS campaign_context,
        NULL::TEXT AS mkt_origin,
        NULL::TEXT AS mkt_channel,
        NULL::TEXT AS mkt_medium,
        NULL::TEXT AS mkt_source,
        COUNT(NULL) as marketing_cost,
        COUNT(NULL) as budget,
        COUNT(NULL) AS tof_users,
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
        COUNT(DISTINCT CASE WHEN tps.status_date_end = 'Active' THEN tps.sk_client ELSE NULL END) AS active_tenant_prospects,
        COUNT(DISTINCT CASE WHEN tps.status_date_end = 'Churned' THEN tps.sk_client ELSE NULL END) AS ongoing_churned_tenant_prospects,
        COUNT(DISTINCT CASE WHEN tps.status_date_start = 'Active' AND tps.status_date_end != 'Churned' THEN tps.sk_client ELSE NULL END) AS retained_tenant_prospects,
        COUNT(NULL) AS new_tenant_prospects,
        COUNT(NULL) AS tenant_prospects,
        COUNT(NULL) AS recovered_tenant_prospects,
        COUNT(NULL) AS tenant_prospect_churns,
        COUNT(NULL) AS tenant_prospect_deactivations_by_renting,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS new_tenant_prospects_target,
        COUNT(NULL) AS tof_users_target
    FROM
        tps_daily AS tps
    WHERE
        date >= CURRENT_DATE - INTERVAL '720 DAY'
        AND date < CURRENT_DATE
    GROUP BY 1,2,3,4,5,6,7,8,9,10
    UNION ALL
    -------------------------------------
    -- Rent Metrics, targets and costs --
    -------------------------------------
    SELECT
        pmmd.dt_event,
        pmmd.city_group,
        CASE
            WHEN pmmd.sk_client IS NOT NULL
                THEN status_date_start
        END AS status_date_start,
        CASE
            WHEN pmmd.dt_event = CURRENT_DATE
                THEN ''
            WHEN pmmd.sk_client IS NOT NULL
                THEN tps.status_date_end
        END AS status_date_end,
        'rent' AS business_context,
        'Rental' AS campaign_context,
        pmmd.mkt_origin,
        pmmd.mkt_channel,
        pmmd.mkt_medium,
        pmmd.mkt_source,
        SUM(pmmd.marketing_cost) as marketing_cost,
        SUM(pmmd.budget) as budget,
        COUNT(NULL) AS tof_users,
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
        COUNT(NULL) AS tof_users_target
    FROM
        datamarts.performance_marketing_metrics_demand AS pmmd
        LEFT JOIN tps_daily AS tps
            ON tps.sk_client = pmmd.sk_client
            AND tps.city_group = pmmd.city_group
            AND tps.date = pmmd.dt_event
    WHERE
        pmmd.dt_event >= CURRENT_DATE - INTERVAL '720 DAY'
    GROUP BY 1,2,3,4,5,6,7,8,9,10
    UNION ALL
    ------------------------
    -- ToF Rental Targets --
    ------------------------
    select
        date::DATE AS dt_event,
        city_group,
        NULL::TEXT AS status_start,
        NULL::TEXT AS status_end,
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
        SUM(daily_tof_target::FLOAT) AS tof_users_target
    FROM
        datalake_gsheets_clean_prod.rental_tof_daily_targets
    GROUP BY 1,2,3,4,5,6,7,8,9,10
    UNION ALL
    ----------------------
    -- ToF Sale Targets --
    ----------------------
    SELECT
        date::DATE AS dt_event,
        city AS city_group,
        NULL::TEXT AS status_start,
        NULL::TEXT AS status_end,
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
        SUM(tof_users_target::FLOAT) AS tof_users_target
    FROM
        datalake_gsheets_clean_prod.sale_tof_daily_targets
    GROUP BY 1,2,3,4,5,6,7,8,9,10
)
SELECT
    ROW_NUMBER() OVER() AS pkey,
    COALESCE(city_group, 'Not Mapped') AS city_group,
    status_start AS status_date_start,
    status_end AS status_date_end,
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
    SUM(tof_users_target) AS tof_users_target
FROM
    events
GROUP BY 2,3,4,5,6,7,8,9,10,11