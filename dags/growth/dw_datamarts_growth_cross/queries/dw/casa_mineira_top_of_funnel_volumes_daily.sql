WITH
status AS (
    SELECT DISTINCT
        dd.date,
        res.sk_real_estate_agency AS advertiser_id,
        dre.real_estate_agency_name AS advertiser_name,
        dre.uf AS advertiser_uf,
        dre.city AS advertiser_city,
        CASE
            WHEN res.status IN ('CREATED', 'REACTIVATED') THEN 'Active'
            ELSE 'Inactive'
        END AS status_date_end,
        lag(
        CASE
            WHEN res.status IN ('CREATED', 'REACTIVATED') THEN 'Active'
            ELSE 'Inactive'
        END
        ) over(partition by res.sk_real_estate_agency order by dd.date) as status_date_start
    FROM dw_casa_mineira_portal.fact_real_estate_status AS res
    JOIN dw_public.dim_date AS dd
        ON dd.date BETWEEN dt_consider_status_started AND DATE_ADD(COALESCE(dt_consider_status_ended, CURRENT_DATE), - 1)
    LEFT JOIN dw_casa_mineira_portal.dim_real_estate_agency AS dre
        ON res.sk_real_estate_agency = dre.sk_real_estate_agency
    WHERE
        dd.date >= CURRENT_DATE - INTERVAL '360 DAY'
        AND res.status IS NOT NULL
),
aux_listings AS (
    SELECT
        dd.date,
        dh.sk_real_estate_agency AS advertiser_id,
        COUNT(DISTINCT dh.sk_house) AS published_listings
    FROM dw_casa_mineira_portal.dim_house AS dh
    JOIN dw_public.dim_date AS dd
        ON dd.date BETWEEN CAST(dh.ts_created AS DATE) AND COALESCE(CAST(dh.ts_disabled AS DATE), CURRENT_DATE) - 1
    GROUP BY 1,2
),
listings AS (
    SELECT
        al.date,
        al.advertiser_id,
        dre.real_estate_agency_name AS advertiser_name,
        dre.uf AS advertiser_uf,
        dre.city AS advertiser_city,
        al.published_listings AS listings_date_end,
        lag(al.published_listings) over(partition by al.advertiser_id order by al.date) as listings_date_start
    FROM aux_listings AS al
    LEFT JOIN dw_casa_mineira_portal.dim_real_estate_agency AS dre
        ON dre.sk_real_estate_agency = al.advertiser_id
    WHERE al.date >= CURRENT_DATE - INTERVAL '360 DAY'
        AND al.published_listings IS NOT NULL
),
aux_budget AS (
    SELECT
        dt_month_started AS dt_budget,
        sk_real_estate_agency AS advertiser_id,
        month_budget,
        LEAD(dt_month_started) OVER(PARTITION BY sk_real_estate_agency ORDER BY dt_month_started) AS dt_next_change
    FROM dw_casa_mineira_portal.fact_real_estate_budget_flows
),
events AS (
    --------------------------------
    -- Top of Funnel Users Portal --
    --------------------------------
    SELECT
        dt_event AS dt,
        CAST(NULL AS INT) id_advertiser,
        CAST(NULL AS STRING) AS advertiser,
        CAST(NULL AS STRING) AS uf_advertiser,
        CAST(NULL AS STRING) AS city_advertiser,
        CAST(NULL AS STRING) AS type_advertiser,
        CAST(NULL AS STRING) AS business_context,
        uf_initials AS uf_listing,
        city_listing AS city_listing,
        mkt_origin AS mkt_origin,
        mkt_channel AS mkt_channel,
        mkt_medium AS mkt_medium,
        mkt_source AS mkt_source,
        mkt_business AS mkt_business,
        city_listing AS city_group,
        CAST(NULL AS STRING) AS status_date_end,
        CAST(NULL AS STRING) AS status_date_start,
        CAST(NULL AS INT) AS listings_date_end,
        CAST(NULL AS INT) AS listings_date_start,
        COUNT(NULL) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(DISTINCT id_device) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target
    FROM
        datalake_top_of_funnel_portal_cm.top_of_funnel_users_portal_casa_mineira
    WHERE
        dt_event >= CURRENT_DATE - INTERVAL '360 DAY' AND mkt_business = 'portal'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    -------------------------------------
    -- Top of Funnel Users Imobiliária --
    -------------------------------------
    SELECT
        dt_event AS dt,
        CAST(NULL AS INT) id_advertiser,
        CAST(NULL AS STRING) AS advertiser,
        CAST(NULL AS STRING) AS uf_advertiser,
        CAST(NULL AS STRING) AS city_advertiser,
        CAST(NULL AS STRING) AS type_advertiser,
        CAST(NULL AS STRING) AS business_context,
        CAST(NULL AS STRING) AS uf_listing,
        CAST(NULL AS STRING) AS city_listing,
        mkt_origin AS mkt_origin,
        mkt_channel AS mkt_channel,
        mkt_medium AS mkt_medium,
        mkt_source AS mkt_source,
        mkt_business AS mkt_business,
        CAST(NULL AS STRING) AS city_group,
        CAST(NULL AS STRING) AS status_date_end,
        CAST(NULL AS STRING) AS status_date_start,
        CAST(NULL AS INT) AS listings_date_end,
        CAST(NULL AS INT) AS listings_date_start,
        COUNT(NULL) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(DISTINCT id_device) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
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
        dt,
        CAST(id_advertiser AS INT) AS id_advertiser,
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
        CAST(NULL AS STRING) AS status_date_end,
        CAST(NULL AS STRING) AS status_date_start,
        CAST(NULL AS INT) AS listings_date_end,
        CAST(NULL AS INT) AS listings_date_start,
        COUNT(NULL) AS budget_advertiser,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) THEN id_house ELSE NULL END) AS listings_contacted,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) THEN contact_flow ELSE NULL END) AS contact_flows,
        COUNT(DISTINCT CASE WHEN (order_new_contact_prospect  = 1) THEN id_prospect ELSE NULL END) AS new_contact_prospects,
        COUNT(DISTINCT id_prospect) AS contact_prospects,
        COUNT(NULL) AS tof_users,
        SUM(cost) AS cost,
        SUM(budget) AS budget,
        COUNT(NULL) AS new_contact_prospects_target,
        SUM(contact_flow_target) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target
FROM
    dw_datamarts.performance_marketing_metrics_portal_casa_mineira
    WHERE
        dt >= CURRENT_DATE - INTERVAL '360 DAY'
        AND mkt_business = 'portal'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    --------------------------------------------
    -- Imobiliaria Metrics, targets and costs --
    --------------------------------------------
    SELECT
        dt,
        1 AS id_advertiser,
        'Casa Mineira por Quinto Andar' AS advertiser,
        'MG' AS uf_advertiser,
        'Belo Horizonte' AS city_advertiser,
        'CM' AS type_advertiser,
        'Sale' AS business_context,
        CAST(NULL AS STRING) AS uf_listing,
        CAST(NULL AS STRING) AS city_listing,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        'imobiliaria' AS mkt_business,
        CAST(NULL AS STRING) AS city_group,
        CAST(NULL AS STRING) AS status_date_end,
        CAST(NULL AS STRING) AS status_date_start,
        CAST(NULL AS INT) AS listings_date_end,
        CAST(NULL AS INT) AS listings_date_start,
        COUNT(NULL) AS budget_advertiser,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) THEN id_house ELSE NULL END) AS listings_contacted,
        COUNT(DISTINCT CASE WHEN (order_new_contact_flow  = 1) THEN id_flow ELSE NULL END) AS contact_flows,
        COUNT(DISTINCT CASE WHEN (order_new_contact_prospect  = 1) THEN id_prospect ELSE NULL END) AS new_contact_prospects,
        COUNT(DISTINCT id_prospect) AS contact_prospects,
        COUNT(NULL) AS tof_users,
        SUM(cost) AS cost,
        SUM(budget) AS budget,
        SUM(new_contact_prospects_target) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target
FROM
    dw_datamarts.performance_marketing_metrics_imobiliaria_casa_mineira
    WHERE
        dt >= CURRENT_DATE - INTERVAL '360 DAY'
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    -----------------------------
    -- ToF Imobiliaria Targets --
    -----------------------------
    SELECT
        dt_target AS dt,
        1 AS id_advertiser,
        'Casa Mineira por Quinto Andar' AS advertiser,
        'MG' AS uf_advertiser,
        'Belo Horizonte' AS city_advertiser,
        'CM' AS type_advertiser,
        'Sale' AS business_context,
        CAST(NULL AS STRING) AS uf_listing,
        CAST(NULL AS STRING) AS city_listing,
        CAST(NULL AS STRING) AS mkt_origin,
        CASE
          WHEN mkt_channel = 'Paid' THEN 'Paid Acquisition'
          ELSE mkt_channel
        END AS mkt_channel,
        mkt_medium AS mkt_medium,
        mkt_source AS mkt_source,
        'imobiliaria' AS mkt_business,
        city_group,
        CAST(NULL AS STRING) AS status_date_end,
        CAST(NULL AS STRING) AS status_date_start,
        CAST(NULL AS INT) AS listings_date_end,
        CAST(NULL AS INT) AS listings_date_start,
        COUNT(NULL) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(NULL) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        SUM(tof_daily_target) AS tof_users_target
    FROM datalake_gsheets_clean.targets_casa_mineira_tof_daily
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    ------------------------
    -- Status Advertisers --
    ------------------------
    SELECT
        date AS dt,
        advertiser_id AS id_advertiser,
        advertiser_name AS advertiser,
        advertiser_uf AS uf_advertiser,
        advertiser_city AS city_advertiser,
        CASE WHEN advertiser_id = 1 THEN 'CM'
            WHEN advertiser_id = 164 THEN '5A'
            ELSE 'Client'
        END AS type_advertiser,
        CAST(NULL AS STRING) AS business_context,
        CAST(NULL AS STRING) AS uf_listing,
        CAST(NULL AS STRING) AS city_listing,
        CAST(NULL AS STRING) AS mkt_origin,
        CAST(NULL AS STRING) AS mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CASE
            WHEN advertiser_id = 1 THEN 'imobiliaria'
            ELSE 'portal'
        END AS mkt_business,
        CAST(NULL AS STRING) AS city_group,
        status_date_end,
        status_date_start,
        CAST(NULL AS INT) AS listings_date_end,
        CAST(NULL AS INT) AS listings_date_start,
        COUNT(NULL) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(NULL) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
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
        dd.date AS dt,
        ab.advertiser_id AS id_advertiser,
        dre.real_estate_agency_name AS advertiser,
        dre.uf AS uf_advertiser,
        dre.city AS city_advertiser,
        CASE WHEN advertiser_id = 1 THEN 'CM'
            WHEN advertiser_id = 164 THEN '5A'
            ELSE 'Client'
        END AS type_advertiser,
        CAST(NULL AS STRING) AS business_context,
        CAST(NULL AS STRING) AS uf_listing,
        CAST(NULL AS STRING) AS city_listing,
        CAST(NULL AS STRING) AS mkt_origin,
        CAST(NULL AS STRING) AS mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CASE
            WHEN advertiser_id = 1 THEN 'imobiliaria'
            ELSE 'portal'
        END AS mkt_business,
        CAST(NULL AS STRING) AS city_group,
        CAST(NULL AS STRING) AS status_date_end,
        CAST(NULL AS STRING) AS status_date_start,
        CAST(NULL AS INT) AS listings_date_end,
        CAST(NULL AS INT) AS listings_date_start,
        SUM(month_budget / CAST((DATEDIFF(dd.month_end, dd.month_start) + 1) AS FLOAT)) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(NULL) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target
    FROM aux_budget AS ab
    JOIN dw_public.dim_date AS dd
        ON dd.date BETWEEN dt_budget AND COALESCE(dt_next_change, CURRENT_DATE) - 1
    LEFT JOIN dw_casa_mineira_portal.dim_real_estate_agency AS dre
        ON dre.sk_real_estate_agency = ab.advertiser_id
    WHERE
        dd.date >= CURRENT_DATE - INTERVAL '360 DAY'
        AND month_budget IS NOT NULL
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
    UNION ALL
    --------------------------
    -- Listings Advertisers --
    --------------------------
    SELECT
        date AS dt,
        advertiser_id AS id_advertiser,
        advertiser_name AS advertiser,
        advertiser_uf AS uf_advertiser,
        advertiser_city AS city_advertiser,
        CASE WHEN advertiser_id = 1 THEN 'CM'
            WHEN advertiser_id = 164 THEN '5A'
            ELSE 'Client'
        END AS type_advertiser,
        CAST(NULL AS STRING) AS business_context,
        CAST(NULL AS STRING) AS uf_listing,
        CAST(NULL AS STRING) AS city_listing,
        CAST(NULL AS STRING) AS mkt_origin,
        CAST(NULL AS STRING) AS mkt_channel,
        CAST(NULL AS STRING) AS mkt_medium,
        CAST(NULL AS STRING) AS mkt_source,
        CASE
            WHEN advertiser_id = 1 THEN 'imobiliaria'
            ELSE 'portal'
        END AS mkt_business,
        CAST(NULL AS STRING) AS city_group,
        CAST(NULL AS STRING) AS status_date_end,
        CAST(NULL AS STRING) AS status_date_start,
        listings_date_end,
        listings_date_start,
        COUNT(NULL) AS budget_advertiser,
        0 AS listings_contacted,
        0 AS contact_flows,
        0 AS new_contact_prospects,
        0 AS contact_prospects,
        COUNT(NULL) AS tof_users,
        0.0 AS cost,
        COUNT(NULL) AS budget,
        COUNT(NULL) AS new_contact_prospects_target,
        COUNT(NULL) AS contact_flow_target,
        COUNT(NULL) AS tof_users_target
    FROM
        listings
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
)
SELECT
    ROW_NUMBER() OVER(ORDER BY dt) AS pkey,
    dt,
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
    status_date_end,
    status_date_start,
    listings_date_end,
    listings_date_start,
    SUM(budget_advertiser) AS budget_advertiser,
    SUM(listings_contacted) AS listings_contacted,
    SUM(contact_flows) AS contact_flows,
    SUM(new_contact_prospects) AS new_contact_prospects,
    SUM(contact_prospects) AS contact_prospects,
    SUM(tof_users) AS tof_users,
    SUM(cost) AS cost,
    SUM(budget) AS budget,
    SUM(new_contact_prospects_target) AS new_contact_prospects_target,
    SUM(contact_flow_target) AS contact_flow_target,
    SUM(tof_users_target) AS tof_users_target
FROM
    events
GROUP BY 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20