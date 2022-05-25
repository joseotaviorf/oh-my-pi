WITH
info_status AS (
    SELECT DISTINCT
        dd.month_start,
        dd.date,
        res.sk_real_estate_agency AS advertiser_id,
        dre.real_estate_agency_name AS advertiser_name,
        dre.uf AS advertiser_uf,
        dre.city AS advertiser_city,
        CASE
            WHEN res.status IN ('CREATED', 'REACTIVATED') THEN 'Active'
            ELSE 'Inactive'
        END AS status,
        MAX(dd.date) OVER(PARTITION BY res.sk_real_estate_agency, DATE_TRUNC('MONTH', dd.date)) AS last_status_start
    FROM
        dw_casa_mineira_portal.fact_real_estate_status AS res
    JOIN dw_public.dim_date AS dd
        ON dd.date BETWEEN dt_consider_status_started AND DATE_ADD(COALESCE(dt_consider_status_ended, CURRENT_DATE()), -1)
    LEFT JOIN dw_casa_mineira_portal.dim_real_estate_agency AS dre
        ON res.sk_real_estate_agency = dre.sk_real_estate_agency
    WHERE
        DATE_TRUNC('MONTH', dd.date) >= DATE_TRUNC('MONTH', CURRENT_DATE - INTERVAL '1 YEAR')
        AND res.status IS NOT NULL
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
daily_listings AS (
    SELECT
        dd.date,
        dh.sk_real_estate_agency AS advertiser_id,
        COUNT(DISTINCT dh.sk_house) AS published_listings
    FROM dw_casa_mineira_portal.dim_house AS dh
    JOIN dw_public.dim_date AS dd
        ON dd.date BETWEEN dh.ts_created::DATE AND COALESCE(dh.ts_disabled::DATE, CURRENT_DATE) - 1
    GROUP BY 1,2
),
aux_listings AS (
    SELECT DISTINCT
        DATE_TRUNC('MONTH', dl.date) AS month_start,
        dl.date,
        dl.advertiser_id,
        dre.real_estate_agency_name AS advertiser_name,
        dre.uf AS advertiser_uf,
        dre.city AS advertiser_city,
        published_listings,
        MAX(dl.date) OVER(PARTITION BY dl.advertiser_id, DATE_TRUNC('MONTH', dl.date)) AS last_start
    FROM
        daily_listings AS dl
    LEFT JOIN dw_casa_mineira_portal.dim_real_estate_agency AS dre
    ON dre.sk_real_estate_agency = dl.advertiser_id
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
    FROM aux_listings
    WHERE
        date = last_start
),
events AS (
    --------------------------------
    -- Top of Funnel Users Portal --
    --------------------------------
    SELECT
        DATE_TRUNC('MONTH', dt_event) AS month_start,
        NULL::INT id_advertiser,
        NULL::STRING AS advertiser,
        NULL::STRING AS uf_advertiser,
        NULL::STRING AS city_advertiser,
        NULL::STRING AS type_advertiser,
        NULL::STRING AS business_context,
        uf_initials AS uf_listing,
        city_listing AS city_listing,
        mkt_origin AS mkt_origin,
        mkt_channel AS mkt_channel,
        mkt_medium AS mkt_medium,
        mkt_source AS mkt_source,
        mkt_business AS mkt_business,
        city_listing AS city_group,
        NULL::STRING AS status_month_end,
        NULL::STRING AS status_month_start,
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
        COUNT(NULL) AS tof_users_target
    FROM
        datalake_top_of_funnel_portal_cm.top_of_funnel_users_portal_casa_mineira
    WHERE
        dt_event >= CURRENT_DATE - INTERVAL '360 DAY' AND mkt_business = 'portal'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    ------------------------------------
    -- Top of Funnel Users Imobilária --
    ------------------------------------
    SELECT
        DATE_TRUNC('MONTH', dt_event) AS month_start,
        NULL::INT id_advertiser,
        NULL::STRING AS advertiser,
        NULL::STRING AS uf_advertiser,
        NULL::STRING AS city_advertiser,
        NULL::STRING AS type_advertiser,
        NULL::STRING AS business_context,
        NULL::STRING AS uf_listing,
        NULL::STRING AS city_listing,
        mkt_origin AS mkt_origin,
        mkt_channel AS mkt_channel,
        mkt_medium AS mkt_medium,
        mkt_source AS mkt_source,
        mkt_business AS mkt_business,
        NULL::STRING AS city_group,
        NULL::STRING AS status_month_end,
        NULL::STRING AS status_month_start,
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
        COUNT(NULL) AS tof_users_target
    FROM
        datalake_top_of_funnel_portal_cm.top_of_funnel_users_portal_casa_mineira
    WHERE
        dt_event >= CURRENT_DATE - INTERVAL '360 DAY' AND mkt_business = 'imobiliaria'
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
        NULL::STRING AS status_month_end,
        NULL::STRING AS status_month_start,
        NULL::INT AS listings_month_end,
        NULL::INT AS listings_month_start,
        COUNT(NULL) AS budget_advertiser,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) THEN id_house ELSE NULL END) AS listings_contacted,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) THEN contact_flow ELSE NULL END) AS contact_flows,
        COUNT(DISTINCT CASE WHEN (order_new_contact_prospect  = 1) THEN id_prospect ELSE NULL END) AS new_contact_prospects,
        COUNT(DISTINCT CASE WHEN dt < CURRENT_DATE THEN id_prospect ELSE NULL END) AS contact_prospects,
        COUNT(NULL) AS tof_users,
        SUM(CASE WHEN dt < CURRENT_DATE THEN cost ELSE NULL END) AS cost,
        SUM(CASE WHEN dt < CURRENT_DATE THEN budget ELSE NULL END) AS budget,
        SUM(budget) AS budget_full_month,
        COUNT(NULL) AS new_contact_prospects_target,
        SUM(CASE WHEN dt < CURRENT_DATE THEN contact_flow_target ELSE NULL END) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target
FROM
    dw_datamarts_growth.performance_marketing_metrics_portal_casa_mineira
    WHERE
        dt >= CURRENT_DATE - INTERVAL '360 DAY'
        AND mkt_business = 'portal'
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
        NULL::STRING AS uf_listing,
        NULL::STRING AS city_listing,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        'imobiliaria' AS mkt_business,
        NULL::STRING AS city_group,
        NULL::STRING AS status_month_end,
        NULL::STRING AS status_month_start,
        NULL::INT AS listings_month_end,
        NULL::INT AS listings_month_start,
        COUNT(NULL) AS budget_advertiser,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) THEN id_house ELSE NULL END) AS listings_contacted,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) THEN id_flow ELSE NULL END) AS contact_flows,
        COUNT(DISTINCT CASE WHEN (order_new_contact_prospect  = 1) THEN id_prospect ELSE NULL END) AS new_contact_prospects,
        COUNT(DISTINCT id_prospect) AS contact_prospects,
        COUNT(NULL) AS tof_users,
        SUM(CASE WHEN dt < CURRENT_DATE THEN cost ELSE NULL END) AS cost,
        SUM(CASE WHEN dt < CURRENT_DATE THEN budget ELSE NULL END) AS budget,
        SUM(budget) AS budget_full_month,
        SUM(CASE WHEN dt < CURRENT_DATE THEN new_contact_prospects_target ELSE NULL END) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target
FROM
    dw_datamarts_growth.performance_marketing_metrics_imobiliaria_casa_mineira
    WHERE
        dt >= CURRENT_DATE - INTERVAL '360 DAY'
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
        NULL::STRING AS uf_listing,
        NULL::STRING AS city_listing,
        NULL::STRING AS mkt_origin,
        CASE
          WHEN mkt_channel = 'Paid' THEN 'Paid Acquisition'
          ELSE mkt_channel
        END AS mkt_channel,
        mkt_medium AS mkt_medium,
        mkt_source AS mkt_source,
        'imobiliaria' AS mkt_business,
        city_group,
        NULL::STRING AS status_month_end,
        NULL::STRING AS status_month_start,
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
        SUM(tof_monthly_target) AS tof_users_target
    FROM datalake_gsheets_clean.targets_casa_mineira_tof_monthly
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    -----------------------------
    -- ToF Portal Targets --
    -----------------------------
    SELECT
        DATE_TRUNC('MONTH', dt_target) AS month_start,
        NULL::INT AS id_advertiser,
        NULL::STRING AS advertiser,
        NULL::STRING AS uf_advertiser,
        NULL::STRING AS city_advertiser,
        NULL::STRING AS type_advertiser,
        NULL::STRING AS business_context,
        NULL::STRING AS uf_listing,
        NULL::STRING AS city_listing,
        NULL::STRING AS mkt_origin,
        NULL::STRING AS mkt_channel,
        mkt_medium,
        mkt_source,
        'portal' AS mkt_business,
        NULL::STRING AS city_group,
        NULL::STRING AS status_month_end,
        NULL::STRING AS status_month_start,
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
        SUM(top_of_funnel_target) AS tof_users_target
    FROM datalake_gsheets_clean.targets_portal_casa_mineira_cost_cf
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
        NULL::STRING AS business_context,
        NULL::STRING AS uf_listing,
        NULL::STRING AS city_listing,
        NULL::STRING AS mkt_origin,
        NULL::STRING AS mkt_channel,
        NULL::STRING AS mkt_medium,
        NULL::STRING AS mkt_source,
        CASE
            WHEN advertiser_id = 1 THEN 'imobiliaria'
            ELSE 'portal'
        END AS mkt_business,
        NULL::STRING AS city_group,
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
        COUNT(NULL) AS tof_users_target
    FROM
        status
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    --------------------------
    -- Budget Advertisers --
    --------------------------
    SELECT
        bf.dt_month_started AS month_start,
        bf.sk_real_estate_agency AS id_advertiser,
        dre.real_estate_agency_name AS advertiser,
        dre.uf AS uf_advertiser,
        dre.city AS city_advertiser,
        CASE WHEN bf.sk_real_estate_agency = 1 THEN 'CM'
            WHEN bf.sk_real_estate_agency = 164 THEN '5A'
            ELSE 'Client'
        END AS type_advertiser,
        NULL::STRING AS business_context,
        NULL::STRING AS uf_listing,
        NULL::STRING AS city_listing,
        NULL::STRING AS mkt_origin,
        NULL::STRING AS mkt_channel,
        NULL::STRING AS mkt_medium,
        NULL::STRING AS mkt_source,
        CASE
            WHEN bf.sk_real_estate_agency = 1 THEN 'imobiliaria'
            ELSE 'portal'
        END AS mkt_business,
        NULL::STRING AS city_group,
        NULL::STRING AS status_month_end,
        NULL::STRING AS status_month_start,
        NULL::INT AS listings_month_end,
        NULL::INT AS listings_month_start,
        SUM(bf.month_budget) AS budget_advertiser,
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
        COUNT(NULL) AS tof_users_target
    FROM
        dw_casa_mineira_portal.fact_real_estate_budget_flows AS bf
    LEFT JOIN dw_casa_mineira_portal.dim_real_estate_agency AS dre
        ON dre.sk_real_estate_agency = bf.sk_real_estate_agency
    WHERE
        dt_month_started >= CURRENT_DATE - INTERVAL '360 DAY'
        AND month_budget IS NOT NULL
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
        NULL::STRING AS business_context,
        NULL::STRING AS uf_listing,
        NULL::STRING AS city_listing,
        NULL::STRING AS mkt_origin,
        NULL::STRING AS mkt_channel,
        NULL::STRING AS mkt_medium,
        NULL::STRING AS mkt_source,
        CASE
            WHEN advertiser_id = 1 THEN 'imobiliaria'
            ELSE 'portal'
        END AS mkt_business,
        NULL::STRING AS city_group,
        NULL::STRING AS status_month_end,
        NULL::STRING AS status_month_start,
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
        COUNT(NULL) AS tof_users_target
    FROM
        listings
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
)
SELECT
    CAST(ROW_NUMBER() OVER(ORDER BY month_start ASC) AS BIGINT) AS pkey,
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
    SUM(tof_users_target) AS tof_users_target
FROM
    events
GROUP BY 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20