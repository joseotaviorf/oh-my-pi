WITH
---------------------------------------------------------------------------------------------------------
-- Query Casa Mineira Marketing Manual Shared Costs From Sheets (Will be used after for History input) --
---------------------------------------------------------------------------------------------------------
costs AS (
    SELECT
        dt,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        NULL::TEXT utm_campaign,
        campaign_name,
        NULL::TEXT uf_listing,
        NULL::TEXT city_listing,
        NULL::TEXT neighborhood_listing,
        COALESCE(city_group, 'Belo Horizonte') AS city_group,
        NULL::TEXT id_house,
        NULL::TEXT id_client,
        NULL::INT order_new_client,
        NULL::TEXT id_prospect,
        NULL::INT order_new_contact_prospect,
        NULL::TEXT id_flow,
        NULL::INT order_new_contact_flow,
        SUM(cost) cost
    FROM datalake_gsheets_clean_prod.casa_mineira_marketing_manual_shared_costs
    WHERE mkt_business = 'imobiliaria'
        AND dt BETWEEN DATE_ADD('YEAR', -1, CURRENT_DATE) AND DATE_ADD('DAY', -1, CURRENT_DATE)
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18
),
----------------------------------------------------
-- Query Taxonomy Portal Casa Mineira From Sheets --
----------------------------------------------------
taxonomy_portal AS (
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
-------------------------------------------------
-- Query Taxonomy CRM Casa Mineira From Sheets --
-------------------------------------------------
taxonomy_crm AS (
    SELECT
    id,
    origin_contact_name::TEXT,
    media_contact_name::TEXT,
    mkt_channel::TEXT,
    mkt_medium::TEXT,
    mkt_origin::TEXT,
    mkt_source::TEXT
  FROM
      datalake_gsheets_clean_prod.taxonomy_crm_casa_mineira
),
---------------------------------
-- Query Events from Amplitude --
---------------------------------
events AS (
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
        JSON_EXTRACT_PATH_TEXT(user_properties , 'platform') AS app_type
    FROM
        datalake_casa_mineira_amplitude_clean_prod."329001_portal"
    WHERE
        event_type = 'receive_information_clicked'
        AND DATE(ts_event) BETWEEN DATE_ADD('YEAR', -1, CURRENT_DATE) AND CURRENT_DATE
),
----------------------------------------------------------------
-- Query Contacts from the raw data Casa Mineira Portal Clean --
----------------------------------------------------------------
info_contact as (
    SELECT
        c.id_client,
        COALESCE(MD5(c.email), c.phone_number, c.id_client) as id_prospect,
        COALESCE(MD5(c.email), c.phone_number, c.id_client) || '_' || COALESCE(c.id_house, '') as id_flow,
        hp.id AS id_house_portal,
        c.id_house AS id_house_crm,
        MD5(c.email) email_md5,
        c.ts_created,
        c.id_origin,
        c.id_media,
        uf.uf_initials,
        ct.city_name,
        n.neighborhood_name,
        o.origin_contact_name,
        m.media_contact_name,
        ROW_NUMBER() OVER(PARTITION BY COALESCE(MD5(c.email), c.phone_number, c.id_client), c.id_house ORDER BY c.ts_created) AS order_new_contact_flow,
        ROW_NUMBER() OVER(PARTITION BY COALESCE(MD5(c.email), c.phone_number, c.id_client) ORDER BY c.ts_created) AS order_new_contact_prospect,
        ROW_NUMBER() OVER(PARTITION BY c.id_client ORDER BY c.ts_created) AS order_new_client
    FROM
        datalake_casa_mineira_crm_clean_prod.contact AS c
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.house AS h
            ON c.id_house = h.id AND hp.id_real_estate_agency = '1'
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.house AS hp
            ON c.id_house = hp.code
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.neighborhood AS n
            ON h.id_neighborhood = n.id
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.city AS ct
            ON n.id_city = ct.id
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.uf AS uf
            ON ct.id_uf = uf.id
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.origin_contact AS o
            ON c.id_origin = o.id
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.media_contact AS m
            ON c.id_media = m.id
),
contacts as (
    SELECT
        date_add('hour', 3, ts_created) ts_contact, --INTO UTC--
        --TAXONOMY DIMENSIONS
        origin_contact_name,
        media_contact_name,
        --LISTING DIMENSIONS
        uf_initials uf_listing,
        city_name city_listing,
        neighborhood_name neighborhood_listing,
        city_name AS city_group,
        --ID DIMENSIONS
        email_md5,
        id_house_portal,
        id_house_crm AS id_house,
        id_client,
        order_new_client,
        id_prospect,
        order_new_contact_prospect,
        id_flow,
        order_new_contact_flow
    FROM info_contact
        WHERE id_origin != '18' AND id_origin::INT < 21
        AND DATE(date_add('hour', 3, ts_created)) BETWEEN DATE_ADD('YEAR', -1, CURRENT_DATE) AND DATE_ADD('DAY', -1, CURRENT_DATE)
),
-----------------------------------------------------------------------------------------------------------
-- Join Contacts from Prod, Events From Amplitude and Taxonomy from Sheets and introduce NULLs for UNION --
-----------------------------------------------------------------------------------------------------------
results AS (
SELECT
    DATE(c.ts_contact) dt,
    COALESCE(tc.mkt_origin, tp.mkt_origin, 'Other') AS mkt_origin,
    COALESCE(tc.mkt_channel, tp.mkt_channel, 'Not Mapped') AS mkt_channel,
    COALESCE(tc.mkt_medium, tp.mkt_medium, 'Not Mapped') AS mkt_medium,
    COALESCE(tc.mkt_source, tp.mkt_source, 'Not Mapped') AS mkt_source,
    COALESCE(evt.utm_campaign, '') AS utm_campaign,
    NULL::TEXT AS campaign_name,
    c.uf_listing,
    c.city_listing,
    c.neighborhood_listing,
    c.city_group,
    c.id_house,
    c.id_client,
    c.order_new_client,
    c.id_prospect,
    c.order_new_contact_prospect,
    c.id_flow,
    c.order_new_contact_flow,
    0.0 AS cost
FROM
    contacts as c
    LEFT JOIN events evt
        ON evt.email_md5 = c.email_md5
        AND evt.id_house = c.id_house_portal
        AND ABS(DATE_DIFF('SECOND', ts_event, ts_contact)) <= 360
    LEFT JOIN taxonomy_portal AS tp
        ON LOWER(COALESCE(tp.app_type, '')) = LOWER(COALESCE(evt.app_type, ''))
    	AND LOWER(COALESCE(tp.utm_source, '')) = LOWER(COALESCE(evt.utm_source, ''))
    	AND LOWER(COALESCE(tp.utm_medium, '')) = LOWER(COALESCE(evt.utm_medium, ''))
    	AND LOWER(COALESCE(tp.branded, '')) = LOWER(COALESCE(evt.branded, ''))
    LEFT JOIN taxonomy_crm AS tc
        ON LOWER(COALESCE(tc.origin_contact_name, '')) = LOWER(COALESCE(c.origin_contact_name, ''))
    	AND LOWER(COALESCE(tc.media_contact_name, '')) = LOWER(COALESCE(c.media_contact_name, ''))
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18
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