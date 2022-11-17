WITH
------------------------------
-- Query Casa Mineira Costs --
------------------------------
costs AS (
    SELECT
        DATE(NULLIF(id_date, -1)) AS dt,
        NULL::INT AS id_advertiser,
        NULL::TEXT AS advertiser,
        NULL::TEXT AS uf_advertiser,
        NULL::TEXT AS city_advertiser,
        NULL::TEXT AS type_advertiser,
        NULL::TEXT AS business_context,
        NULL::TEXT AS uf_listing,
        NULL::TEXT AS city_listing,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        funnel_side AS mkt_business,
        city_group,
        NULL::TEXT AS utm_campaign,
        campaign_name,
        NULL::INT AS order_new_contact_flow,
        NULL::INT AS order_new_contact_prospect,
        NULL::TEXT AS id_house,
        NULL::TEXT AS id_prospect,
        NULL::TEXT AS contact_flow,
        NULL::FLOAT AS budget_advertiser,
        SUM(cost) AS cost,
        NULL::FLOAT AS budget,
        NULL::FLOAT AS contact_flow_target
    FROM datalake_casa_mineira_marketing_costs_prod.daily_costs
    WHERE DATE(NULLIF(id_date, -1)) BETWEEN DATE_ADD('YEAR', -1, CURRENT_DATE) AND DATE_ADD('DAY', -1, CURRENT_DATE)
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22
),
----------------------------------------------------
-- Query Taxonomy Portal Casa Mineira From Sheets --
----------------------------------------------------
taxonomy AS (
    SELECT
    id,
    app_type::TEXT,
    utm_source::TEXT,
    utm_medium::TEXT,
    branded::TEXT,
    mkt_category,
    mkt_flow,
    mkt_completion,
    mkt_channel::TEXT,
    mkt_medium::TEXT,
    mkt_origin::TEXT,
    mkt_source::TEXT,
    mkt_platform
  FROM
      datalake_gsheets_clean_prod.taxonomy_portal_casa_mineira
),
---------------------------------
-- Query Events from Amplitude --
---------------------------------
info_events AS (
    SELECT
        ts_event,
        JSON_EXTRACT_PATH_TEXT(event_properties, 'email_md5') AS email_md5,
        JSON_EXTRACT_PATH_TEXT(event_properties, 'house_id') AS id_house,
        JSON_EXTRACT_PATH_TEXT(user_properties, 'utm_source') AS utm_source,
        JSON_EXTRACT_PATH_TEXT(user_properties, 'utm_medium') AS utm_medium,
        JSON_EXTRACT_PATH_TEXT(user_properties, 'utm_campaign') AS utm_campaign,
        CASE
            WHEN UPPER(JSON_EXTRACT_PATH_TEXT(user_properties, 'utm_campaign')) LIKE '%BRANDED%'
                        AND UPPER(JSON_EXTRACT_PATH_TEXT(user_properties, 'utm_campaign')) NOT LIKE '%NON-BRANDED%'
              THEN 'Branded'
            ELSE 'Outro'
        END AS branded,
        JSON_EXTRACT_PATH_TEXT(user_properties , 'platform') AS app_type,
        ROW_NUMBER() OVER(PARTITION BY JSON_EXTRACT_PATH_TEXT(event_properties, 'email_md5'), JSON_EXTRACT_PATH_TEXT(event_properties, 'house_id') ORDER BY ts_event) AS rn
    FROM
        datalake_casa_mineira_amplitude_clean_prod."329001_portal"
    WHERE
        event_type = 'receive_information_clicked'
        AND DATE(ts_event) BETWEEN DATE_ADD('YEAR', -1, CURRENT_DATE) AND CURRENT_DATE
),
------------------------------------------------------
-- Filter the first contact flow cohort from events --
------------------------------------------------------
events AS (
    SELECT
        ts_event,
        email_md5,
        id_house,
        utm_source,
        utm_medium,
        utm_campaign,
        branded,
        app_type
    FROM
        info_events
    WHERE
        rn=1
),
----------------------------------------------------------------
-- Query Contacts from the raw data Casa Mineira Portal Clean --
----------------------------------------------------------------
contacts as (
    SELECT
        date_add('hour', 3, c.ts_created) AS ts_contact, --INTO UTC--
        --ADVERTISER DIMENSIONS
        rea.id AS id_advertiser,
        rea.real_estate_agency_name AS advertiser,
        ufa.uf_initials AS uf_advertiser,
        cta.city_name AS city_advertiser,
        CASE WHEN rea.id IN ('1') THEN 'CM'
            WHEN rea.id IN ('164') THEN '5A'
            ELSE 'Client'
        END AS type_advertiser,
        --LISTING DIMENSIONS
        CASE
            WHEN h.goal='venda' THEN 'Sale'
            WHEN h.goal='aluguel' THEN 'Rent'
        END AS business_context,
        ufl.uf_initials AS uf_listing,
        ctl.city_name AS city_listing,
        ctl.city_name AS city_group,
        -- TAXONOMY DIMENSIONS
        CASE
            WHEN rea.id IN ('1') THEN 'imobiliaria'
            ELSE 'portal'
        END AS mkt_business,
        --ID DIMENSIONS
        MD5(c.email) || '_' || c.id_house AS id_contact,
        MD5(c.email) AS email_md5,
        c.id_house,
        ROW_NUMBER() OVER(PARTITION BY c.email, c.id_house ORDER BY c.ts_created) AS order_new_contact_flow,
        ROW_NUMBER() OVER(PARTITION BY c.email ORDER BY c.ts_created) AS order_new_contact_prospect
    FROM datalake_casa_mineira_portal_clean_prod.contact AS c
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.house AS h
            ON c.id_house = h.id
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.real_estate_agency AS rea
            ON h.id_real_estate_agency = rea.id
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.neighborhood AS n
            ON n.id = h.id_neighborhood
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.city AS ctl
            ON n.id_city = ctl.id
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.city AS cta
            ON rea.id_city = cta.id
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.uf AS ufl
            ON ctl.id_uf = ufl.id
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.uf AS ufa
            ON cta.id_uf = ufa.id
),
-----------------------------------------------------------------------------------------------------------
-- Join Contacts from Prod, Events From Amplitude and Taxonomy from Sheets and introduce NULLs for UNION --
-----------------------------------------------------------------------------------------------------------
results AS (
SELECT
    DATE(c.ts_contact) AS dt,
    c.id_advertiser::INT,
    c.advertiser,
    c.uf_advertiser,
    c.city_advertiser,
    c.type_advertiser,
    c.business_context,
    c.uf_listing,
    c.city_listing,
    COALESCE(t.mkt_origin, 'Other') AS mkt_origin,
    COALESCE(t.mkt_channel, 'Not Mapped') AS mkt_channel,
    COALESCE(t.mkt_medium, 'Not Mapped') AS mkt_medium,
    COALESCE(t.mkt_source, 'Not Mapped') AS mkt_source,
    c.mkt_business,
    c.city_group,
    COALESCE(evt.utm_campaign, '') AS utm_campaign,
    NULL::TEXT AS campaign_name,
    order_new_contact_flow,
    order_new_contact_prospect,
    c.id_house,
    c.email_md5 AS id_prospect,
    id_contact AS contact_flow,
    NULL::FLOAT AS budget_advertiser,
    NULL::FLOAT AS cost,
    NULL::FLOAT AS budget,
    NULL::FLOAT AS contact_flow_target
FROM
    contacts as c
    LEFT JOIN events evt
        ON evt.id_house = c.id_house
        AND evt.email_md5 = c.email_md5
        AND ABS(DATEDIFF('SECOND', ts_event, ts_contact)) <= 360
    LEFT JOIN taxonomy AS t
        ON LOWER(COALESCE(t.app_type, '')) = LOWER(COALESCE(evt.app_type, ''))
      and LOWER(COALESCE(t.utm_source, '')) = LOWER(COALESCE(evt.utm_source, ''))
      and LOWER(COALESCE(t.utm_medium, '')) = LOWER(COALESCE(evt.utm_medium, ''))
      and LOWER(COALESCE(t.branded, '')) = LOWER(COALESCE(evt.branded, ''))
WHERE DATE(c.ts_contact) BETWEEN DATE_ADD('YEAR', -1, CURRENT_DATE) AND DATE_ADD('DAY', -1, CURRENT_DATE)
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22
),
-------------------------------------------------------------
-- Query targets from sheets and introduce NULLs for UNION --
-------------------------------------------------------------
targets AS (
    SELECT
        dt_target AS dt,
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
        NULL::TEXT AS utm_campaign,
        NULL::TEXT AS campaign_name,
        NULL::INT AS order_new_contact_flow,
        NULL::INT AS order_new_contact_prospect,
        NULL::TEXT AS id_house,
        NULL::TEXT AS id_prospect,
        NULL::TEXT AS contact_flow,
        NULL::FLOAT AS budget_advertiser,
        NULL::FLOAT AS cost,
        SUM(cost_target) AS budget,
        SUM(contact_flow_target) AS contact_flow_target
    FROM datalake_gsheets_clean_prod.targets_portal_casa_mineira_cost_cf
    WHERE dt_target BETWEEN DATE_ADD('YEAR', -1, CURRENT_DATE) AND DATE_ADD('DAY', -1, CURRENT_DATE)
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22
),
aux_budget AS (
    SELECT
        dt_month_started AS dt_budget,
        sk_real_estate_agency AS advertiser_id,
        month_budget,
        LEAD(dt_month_started) OVER(PARTITION BY sk_real_estate_agency ORDER BY dt_month_started) AS dt_next_change
    FROM casa_mineira_portal.fact_real_estate_budget_flows
),
budget as (
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
        NULL::TEXT AS utm_campaign,
        NULL::TEXT AS campaign_name,
        NULL::INT AS order_new_contact_flow,
        NULL::INT AS order_new_contact_prospect,
        NULL::TEXT AS id_house,
        NULL::TEXT AS id_prospect,
        NULL::TEXT AS contact_flow,
        month_budget / (DATE_DIFF('DAY', dd.month_start, dd.month_end) + 1)::FLOAT AS budget_advertiser,
        NULL::FLOAT AS cost,
        NULL::FLOAT AS budget,
        NULL::FLOAT AS contact_flow_target
    FROM aux_budget AS ab
    JOIN dim_date AS dd
        ON dd.date BETWEEN dt_budget AND COALESCE(dt_next_change, CURRENT_DATE) - 1
    LEFT JOIN casa_mineira_portal.dim_real_estate_agency AS dre
        ON dre.sk_real_estate_agency = ab.advertiser_id
    WHERE
        month_budget IS NOT NULL
)
---------------------------------------------------------
-- UNION Costs, Results, Targets and Advertiser Budget --
---------------------------------------------------------
SELECT
    r.*
FROM
    results AS r

UNION ALL

SELECT
    ct.*
FROM
    costs AS ct

UNION ALL

SELECT
    tgt.*
FROM
    targets AS tgt

UNION ALL

SELECT
    bud.*
FROM
    budget AS bud