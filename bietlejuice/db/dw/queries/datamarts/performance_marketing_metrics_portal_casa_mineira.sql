WITH
---------------------------------------------------------------------------------------------------------
-- Query Casa Mineira Marketing Manual Shared Costs From Sheets (Will be used after for History input) --
---------------------------------------------------------------------------------------------------------
info_costs AS (
    SELECT
        dt,
        city_group,
        campaign_name,
        CASE
            WHEN city_group = '-' THEN 'Nacional'
            WHEN city_group IS NOT NULL THEN city_group
            WHEN mkt_business = 'imobiliaria' THEN '1535'
            WHEN campaign_name ~ '^(\\d+).' THEN SPLIT_PART(campaign_name, '.', 1)
            WHEN campaign_name ~ '^(\\D\\d{3}\\D).' THEN 'Nacional'
            ELSE city_group
        END AS city_group_from_campaign,
        mkt_business,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        SUM(cost) cost
    FROM datalake_gsheets_clean_prod.casa_mineira_marketing_manual_shared_costs
    GROUP BY 1,2,3,4,5,6,7,8,9
),
----------------------------------------------------------------
-- Query costs, join dim_region and introduce NULLs for UNION --
----------------------------------------------------------------
costs AS (
    SELECT
        dt,
        NULL::TEXT id_advertiser,
        NULL::TEXT advertiser,
        NULL::TEXT uf_advertiser,
        NULL::TEXT city_advertiser,
        NULL::TEXT type_advertiser,
        NULL::TEXT uf_listing,
        NULL::TEXT city_listing,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        mkt_business,
        COALESCE(dr.city_group, ict.city_group_from_campaign) city_group,
        NULL::TEXT utm_campaign,
        campaign_name,
        NULL::INT order_new_contact_flow,
        NULL::INT order_new_contact_prospect,
        NULL::TEXT id_house,
        NULL::TEXT id_prospect,
        NULL::TEXT contact_flow,
        SUM(cost) cost
    FROM info_costs ict
        LEFT JOIN dim_region dr
            ON ict.city_group_from_campaign=dr.sk_region
    WHERE dt BETWEEN '2021-06-01' AND DATE_ADD('DAY', -1, CURRENT_DATE)
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21
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
        AND DATE(ts_event) BETWEEN '2021-06-01' AND CURRENT_DATE
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
        date_add('hour', 3, c.ts_created) ts_contact, --INTO UTC--
        --ADVERTISER DIMENSIONS
        rea.id id_advertiser,
        rea.real_estate_agency_name advertiser,
        rea.uf uf_advertiser,
        rea.city as city_advertiser,
        CASE WHEN rea.id IN ('1') THEN 'CM'
            WHEN rea.id IN ('164') THEN '5A'
            ELSE 'Client'
        END AS type_advertiser,
        --LISTING DIMENSIONS
        uf.uf_initials uf_listing,
        ct.city_name city_listing,
        ct.city_name AS city_group,
        -- TAXONOMY DIMENSIONS
        CASE
            WHEN rea.id IN ('1') THEN 'imobiliaria'
            ELSE 'portal'
        END AS mkt_business,
        --ID DIMENSIONS
        MD5(c.email) || '_' || c.id_house as id_contact,
        MD5(c.email) email_md5,
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
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.city AS ct
            ON n.id_city = ct.id
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.uf AS uf
            ON ct.id_uf = uf.id
    WHERE DATE(date_add('hour', 3, c.ts_created)) BETWEEN '2021-06-01' AND DATE_ADD('DAY', -1, CURRENT_DATE)
),
-----------------------------------------------------------------------------------------------------------
-- Join Contacts from Prod, Events From Amplitude and Taxonomy from Sheets and introduce NULLs for UNION --
-----------------------------------------------------------------------------------------------------------
results AS (
SELECT
    DATE(c.ts_contact) dt,
    c.id_advertiser,
    c.advertiser,
    c.uf_advertiser,
    c.city_advertiser,
    c.type_advertiser,
    c.uf_listing,
    c.city_listing,
    COALESCE(t.mkt_origin, 'Portal Casa Mineira') AS mkt_origin,
    COALESCE(t.mkt_channel, 'Other') AS mkt_channel,
    COALESCE(t.mkt_medium, 'Not Mapped') AS mkt_medium,
    COALESCE(t.mkt_source, 'Not Mapped') AS mkt_source,
    c.mkt_business,
    c.city_group,
    COALESCE(evt.utm_campaign, 'Lost Tracking') AS utm_campaign,
    NULL::TEXT AS campaign_name,
    order_new_contact_flow,
    order_new_contact_prospect,
    c.id_house,
    c.email_md5 AS id_prospect,
    id_contact AS contact_flow,
    0.0 AS cost
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
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21
)
-----------------------------
-- UNION Costs and Results --
-----------------------------
SELECT
    r.*
FROM
    results AS r

UNION ALL

SELECT
    ct.*
FROM
    costs AS ct