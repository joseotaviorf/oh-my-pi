WITH
info_status AS (
    SELECT DISTINCT
        DATE_TRUNC('MONTH', date) AS month_start,
        date,
        advertiser_id,
        advertiser_name,
        advertiser_uf,
        advertiser_city,
        status,
        MAX(date) OVER(PARTITION BY advertiser_id, DATE_TRUNC('MONTH', date)) AS last_status_start
    FROM
        datamarts.portal_casa_mineira_advertiser_metrics AS tps
    WHERE
        DATE_TRUNC('MONTH', date) >= DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '1 YEAR')
        AND status IS NOT NULL
),
status AS (
    SELECT
        month_start,
        advertiser_id,
        advertiser_name,
        advertiser_uf,
        advertiser_city,
        status AS status_month_end,
        lag(status) over(partition by advertiser_id order by month_start) as status_month_start
    FROM info_status
    WHERE
        date = last_status_start
),
info_listings AS (
    SELECT DISTINCT
        DATE_TRUNC('MONTH', date) month_start,
        date,
        advertiser_id,
        advertiser_name,
        advertiser_uf,
        advertiser_city,
        published_listings,
        MAX(date) OVER(PARTITION BY advertiser_id, DATE_TRUNC('MONTH', date)) AS last_start
    FROM
        datamarts.portal_casa_mineira_advertiser_metrics AS tps
    WHERE
        DATE_TRUNC('MONTH', date) >= DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '1 YEAR')
        AND published_listings IS NOT NULL
),
listings AS (
    SELECT
        month_start,
        advertiser_id,
        advertiser_name,
        advertiser_uf,
        advertiser_city,
        published_listings AS listings_month_end,
        lag(published_listings) over(partition by advertiser_id order by month_start) as listings_month_start
    FROM info_listings
    WHERE
        date = last_start
),
events AS (
    -------------------------
    -- Top of Funnel Users --
    -------------------------
    SELECT
        DATE_TRUNC('MONTH', dt_event) AS month_start,
        NULL::INT id_advertiser,
        NULL::TEXT AS advertiser,
        NULL::TEXT AS uf_advertiser,
        NULL::TEXT AS city_advertiser,
        NULL::TEXT AS type_advertiser,
        NULL::TEXT AS business_context,
        uf_initials AS uf_listing,
        city_listing AS city_listing,
        mkt_origin AS mkt_origin,
        mkt_channel AS mkt_channel,
        mkt_medium AS mkt_medium,
        mkt_source AS mkt_source,
        mkt_business AS mkt_business,
        city_listing AS city_group,
        NULL::TEXT AS status_month_end,
        NULL::TEXT AS status_month_start,
        NULL::INT AS listings_month_end,
        NULL::INT AS listings_month_start,
        COUNT(NULL) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(DISTINCT id_device) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS budget_full_month,
        COUNT(NULL) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target,
        COUNT(NULL) AS new_contact_prospects_target_full_month,
        COUNT(NULL) AS contact_flow_target_full_month,
        COUNT(NULL) AS tof_users_target_full_month
    FROM
        datalake_top_of_funnel_portal_cm_prod.top_of_funnel_users_portal_casa_mineira
    WHERE
        dt_event >= CURRENT_DATE - INTERVAL '360 DAY'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    ---------------------------------------
    -- Portal Metrics, targets and costs --
    ---------------------------------------
    SELECT
        DATE_TRUNC('MONTH', dt) AS month_start,
        id_advertiser::INT,
        advertiser,
        uf_advertiser,
        city_advertiser,
        type_advertiser,
        business_context,
        uf_listing,
        city_listing,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        'portal' AS mkt_business,
        city_group,
        NULL::TEXT AS status_month_end,
        NULL::TEXT AS status_month_start,
        NULL::INT AS listings_month_end,
        NULL::INT AS listings_month_start,
        COUNT(NULL) AS budget_advertiser,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) AND dt < CURRENT_DATE THEN id_house ELSE NULL END) AS listings_contacted,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) AND dt < CURRENT_DATE THEN contact_flow ELSE NULL END) AS contact_flows,
        COUNT(DISTINCT CASE WHEN (order_new_contact_prospect  = 1) AND dt < CURRENT_DATE THEN id_prospect ELSE NULL END) AS new_contact_prospects,
        COUNT(DISTINCT CASE WHEN dt < CURRENT_DATE THEN id_prospect ELSE NULL END) AS contact_prospects,
        COUNT(NULL) AS tof_users,
        SUM(CASE WHEN dt < CURRENT_DATE THEN cost ELSE NULL END) AS cost,
        SUM(CASE WHEN dt < CURRENT_DATE THEN budget ELSE NULL END) AS budget,
        SUM(budget) AS budget_full_month,
        COUNT(NULL) AS new_contact_prospects_target,
        SUM(CASE WHEN dt < CURRENT_DATE THEN contact_flow_target ELSE NULL END) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target,
        COUNT(NULL) AS new_contact_prospects_target_full_month,
        SUM(contact_flow_target) AS contact_flow_target_full_month,
        COUNT(NULL) AS tof_users_target_full_month
FROM
    datamarts.performance_marketing_metrics_portal_casa_mineira
    WHERE
        dt >= LAST_DAY(CURRENT_DATE) - INTERVAL '360 DAY'
        AND mkt_business = 'portal'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    -----------------------------
    -- ToF Portal Targets --
    -----------------------------
    SELECT
        DATE_TRUNC('MONTH', dt_target) AS month_start,
        NULL::INT AS id_advertiser,
        NULL::TEXT AS advertiser,
        NULL::TEXT AS uf_advertiser,
        NULL::TEXT AS city_advertiser,
        NULL::TEXT AS type_advertiser,
        NULL::TEXT AS business_context,
        NULL::TEXT AS uf_listing,
        NULL::TEXT AS city_listing,
        NULL::TEXT AS mkt_origin,
        NULL::TEXT AS mkt_channel,
        mkt_medium,
        mkt_source,
        'portal' AS mkt_business,
        NULL::TEXT AS city_group,
        NULL::TEXT AS status_month_end,
        NULL::TEXT AS status_month_start,
        NULL::INT AS listings_month_end,
        NULL::INT AS listings_month_start,
        COUNT(NULL) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(NULL) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS budget_full_month,
        COUNT(NULL) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        SUM(CASE WHEN dt_target < CURRENT_DATE THEN top_of_funnel_target ELSE NULL END) AS tof_users_target,
        COUNT(NULL) AS new_contact_prospects_target_full_month,
        COUNT(NULL) AS contact_flow_target_full_month,
        SUM(top_of_funnel_target) AS tof_users_target_full_month
    FROM datalake_gsheets_clean_prod.targets_portal_casa_mineira_cost_cf
    WHERE
        dt_target >= LAST_DAY(CURRENT_DATE) - INTERVAL '360 DAY'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    --------------------------------------------
    -- Imobiliaria Metrics, targets and costs --
    --------------------------------------------
    SELECT
        DATE_TRUNC('MONTH', dt) AS month_start,
        1 AS id_advertiser,
        'Casa Mineira por Quinto Andar' AS advertiser,
        'MG' AS uf_advertiser,
        'Belo Horizonte' AS city_advertiser,
        'CM' AS type_advertiser,
        'Sale' AS business_context,
        uf_listing,
        city_listing,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        'imobiliaria' AS mkt_business,
        city_group,
        NULL::TEXT AS status_month_end,
        NULL::TEXT AS status_month_start,
        NULL::INT AS listings_month_end,
        NULL::INT AS listings_month_start,
        COUNT(NULL) AS budget_advertiser,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) AND dt < CURRENT_DATE THEN id_house ELSE NULL END) AS listings_contacted,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) AND dt < CURRENT_DATE  THEN id_flow ELSE NULL END) AS contact_flows,
        COUNT(DISTINCT CASE WHEN (order_new_contact_prospect  = 1) AND dt < CURRENT_DATE  THEN id_prospect ELSE NULL END) AS new_contact_prospects,
        COUNT(DISTINCT id_prospect) AS contact_prospects,
        COUNT(NULL) AS tof_users,
        SUM(CASE WHEN dt < CURRENT_DATE THEN cost ELSE NULL END) AS cost,
        SUM(CASE WHEN dt < CURRENT_DATE THEN budget ELSE NULL END) AS budget,
        SUM(budget) AS budget_full_month,
        SUM(CASE WHEN dt < CURRENT_DATE THEN new_contact_prospects_target ELSE NULL END) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target,
        SUM(new_contact_prospects_target) AS new_contact_prospects_target_full_month,
        COUNT(NULL) AS contact_flow_target_full_month,
        COUNT(NULL) AS tof_users_target_full_month
FROM
    datamarts.performance_marketing_metrics_imobiliaria_casa_mineira
    WHERE
        dt >= LAST_DAY(CURRENT_DATE) - INTERVAL '360 DAY'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    -----------------------------
    -- ToF Imobiliaria Targets --
    -----------------------------
    SELECT
        month_target::DATE month_start,
        1 AS id_advertiser,
        'Casa Mineira por Quinto Andar' AS advertiser,
        'MG' AS uf_advertiser,
        'Belo Horizonte' AS city_advertiser,
        'CM' AS type_advertiser,
        'Sale' AS business_context,
        NULL::TEXT AS uf_listing,
        NULL::TEXT AS city_listing,
        NULL::TEXT AS mkt_origin,
        CASE
          WHEN mkt_channel = 'Paid' THEN 'Paid Acquisition'
          ELSE mkt_channel
        END AS mkt_channel,
        mkt_medium AS mkt_medium,
        mkt_source AS mkt_source,
        'imobiliaria' AS mkt_business,
        city_group,
        NULL::TEXT AS status_month_end,
        NULL::TEXT AS status_month_start,
        NULL::INT AS listings_month_end,
        NULL::INT AS listings_month_start,
        COUNT(NULL) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(NULL) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS budget_full_month,
        COUNT(NULL) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        SUM(tof_monthly_target) AS tof_users_target,
        COUNT(NULL) AS new_contact_prospects_target_full_month,
        COUNT(NULL) AS contact_flow_target_full_month,
        COUNT(NULL) AS tof_users_target_full_month
    FROM datalake_gsheets_clean_prod.targets_casa_mineira_tof_monthly
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    ------------------------
    -- Status Advertisers --
    ------------------------
    SELECT
        month_start::DATE,
        advertiser_id AS id_advertiser,
        advertiser_name AS advertiser,
        advertiser_uf AS uf_advertiser,
        advertiser_city AS city_advertiser,
        CASE WHEN advertiser_id = 1 THEN 'CM'
            WHEN advertiser_id = 164 THEN '5A'
            ELSE 'Client'
        END AS type_advertiser,
        NULL::TEXT AS business_context,
        NULL::TEXT AS uf_listing,
        NULL::TEXT AS city_listing,
        NULL::TEXT AS mkt_origin,
        NULL::TEXT AS mkt_channel,
        NULL::TEXT AS mkt_medium,
        NULL::TEXT AS mkt_source,
        CASE
            WHEN advertiser_id = 1 THEN 'imobiliaria'
            ELSE 'portal'
        END AS mkt_business,
        NULL::TEXT AS city_group,
        status_month_end,
        status_month_start,
        NULL::INT AS listings_month_end,
        NULL::INT AS listings_month_start,
        COUNT(NULL) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(NULL) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS budget_full_month,
        COUNT(NULL) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target,
        COUNT(NULL) AS new_contact_prospects_target_full_month,
        COUNT(NULL) AS contact_flow_target_full_month,
        COUNT(NULL) AS tof_users_target_full_month
    FROM
        status
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    --------------------------
    -- Budget Advertisers --
    --------------------------
    SELECT
        DATE_TRUNC('MONTH', date) AS month_start,
        advertiser_id AS id_advertiser,
        advertiser_name AS advertiser,
        advertiser_uf AS uf_advertiser,
        advertiser_city AS city_advertiser,
        CASE WHEN advertiser_id = 1 THEN 'CM'
            WHEN advertiser_id = 164 THEN '5A'
            ELSE 'Client'
        END AS type_advertiser,
        NULL::TEXT AS business_context,
        NULL::TEXT AS uf_listing,
        NULL::TEXT AS city_listing,
        NULL::TEXT AS mkt_origin,
        NULL::TEXT AS mkt_channel,
        NULL::TEXT AS mkt_medium,
        NULL::TEXT AS mkt_source,
        CASE
            WHEN advertiser_id = 1 THEN 'imobiliaria'
            ELSE 'portal'
        END AS mkt_business,
        NULL::TEXT AS city_group,
        NULL::TEXT AS status_month_end,
        NULL::TEXT AS status_month_start,
        NULL::INT AS listings_month_end,
        NULL::INT AS listings_month_start,
        SUM(daily_budget) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(NULL) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS budget_full_month,
        COUNT(NULL) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target,
        COUNT(NULL) AS new_contact_prospects_target_full_month,
        COUNT(NULL) AS contact_flow_target_full_month,
        COUNT(NULL) AS tof_users_target_full_month
    FROM
        datamarts.portal_casa_mineira_advertiser_metrics
    WHERE
        date >= CURRENT_DATE - INTERVAL '360 DAY'
        AND daily_budget IS NOT NULL
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    --------------------------
    -- Listings Advertisers --
    --------------------------
    SELECT
        month_start::DATE,
        advertiser_id AS id_advertiser,
        advertiser_name AS advertiser,
        advertiser_uf AS uf_advertiser,
        advertiser_city AS city_advertiser,
        CASE WHEN advertiser_id = 1 THEN 'CM'
            WHEN advertiser_id = 164 THEN '5A'
            ELSE 'Client'
        END AS type_advertiser,
        NULL::TEXT AS business_context,
        NULL::TEXT AS uf_listing,
        NULL::TEXT AS city_listing,
        NULL::TEXT AS mkt_origin,
        NULL::TEXT AS mkt_channel,
        NULL::TEXT AS mkt_medium,
        NULL::TEXT AS mkt_source,
        CASE
            WHEN advertiser_id = 1 THEN 'imobiliaria'
            ELSE 'portal'
        END AS mkt_business,
        NULL::TEXT AS city_group,
        NULL::TEXT AS status_month_end,
        NULL::TEXT AS status_month_start,
        listings_month_end,
        listings_month_start,
        COUNT(NULL) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(NULL) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS budget_full_month,
        COUNT(NULL) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target,
        COUNT(NULL) AS new_contact_prospects_target_full_month,
        COUNT(NULL) AS contact_flow_target_full_month,
        COUNT(NULL) AS tof_users_target_full_month
    FROM
        listings
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
)
SELECT
    ROW_NUMBER() OVER() AS pkey,
    month_start,
    id_advertiser,
    advertiser,
    uf_advertiser,
    city_advertiser,
    type_advertiser,
    business_context,
    uf_listing,
    city_listing,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    mkt_business,
    city_group,
    status_month_end,
    status_month_start,
    listings_month_end,
    listings_month_start,
    SUM(budget_advertiser) AS budget_advertiser,
    SUM(listings_contacted) AS listings_contacted,
    SUM(contact_flows) AS contact_flows,
    SUM(new_contact_prospects) AS new_contact_prospects,
    SUM(contact_prospects) AS contact_prospects,
    SUM(tof_users) AS tof_users,
    SUM(cost) AS cost,
    SUM(budget) AS budget,
    SUM(budget_full_month) AS budget_full_month,
    SUM(new_contact_prospects_target) AS new_contact_prospects_target,
    SUM(contact_flow_target) AS contact_flow_target,
    SUM(tof_users_target) AS tof_users_target,
    SUM(new_contact_prospects_target_full_month) AS new_contact_prospects_target_full_month,
    SUM(contact_flow_target_full_month) AS contact_flow_target_full_month,
    SUM(tof_users_target_full_month) AS tof_users_target_full_month
FROM
    events
GROUP BY 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20