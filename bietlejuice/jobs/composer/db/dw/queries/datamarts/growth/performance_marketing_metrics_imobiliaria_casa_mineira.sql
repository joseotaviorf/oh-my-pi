WITH
---------------------------------------------------------------------------------------------------------
-- Query Casa Mineira Marketing Manual Shared Costs From Sheets (Will be used after for History input) --
---------------------------------------------------------------------------------------------------------
costs AS (
    SELECT
        DATE(NULLIF(id_date, -1)) AS dt,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        NULL::TEXT utm_campaign,
        campaign_name,
        NULL::TEXT uf_listing,
        NULL::TEXT city_listing,
        NULL::TEXT neighborhood_listing,
        city_group,
        NULL::TEXT id_house,
        NULL::TEXT id_client,
        NULL::INT order_new_client,
        NULL::TEXT id_prospect,
        NULL::INT order_new_contact_prospect,
        NULL::TEXT id_flow,
        NULL::INT order_new_contact_flow,
        NULL::TEXT AS id_visit,
        NULL::TEXT AS id_house_booked,
        NULL::TEXT AS id_client_booked,
        NULL::TEXT AS listing_type,
        NULL::TEXT AS uf_listing_booked,
        NULL::TEXT AS city_listing_booked,
        NULL::TEXT AS neighborhood_listing_booked,
        NULL::TEXT AS type_visit,
        NULL::INT AS order_new_visit_booked,
        SUM(cost) cost,
        0.0 AS budget,
        0.0 AS new_contact_prospects_target,
        0.0 AS new_buyer_prospect_target
    FROM datalake_casa_mineira_marketing_costs_prod.daily_costs
    WHERE funnel_side = 'imobiliaria'
        AND DATE(NULLIF(id_date, -1)) BETWEEN DATE_ADD('YEAR', -1, CURRENT_DATE) AND DATE_ADD('DAY', -1, CURRENT_DATE)
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27
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
info_contact as (
    SELECT
        c.id_client,
        COALESCE(c.id_client, c.phone_number, MD5(c.email)) as id_prospect,
        COALESCE(c.id_client, c.phone_number, MD5(c.email)) || '_' || COALESCE(c.id_house, '') as id_flow,
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
        ROW_NUMBER() OVER(PARTITION BY COALESCE(c.id_client, c.phone_number, MD5(c.email)), c.id_house ORDER BY c.ts_created) AS order_new_contact_flow,
        ROW_NUMBER() OVER(PARTITION BY COALESCE(c.id_client, c.phone_number, MD5(c.email)) ORDER BY c.ts_created) AS order_new_contact_prospect,
        ROW_NUMBER() OVER(PARTITION BY c.id_client ORDER BY c.ts_created) AS order_new_client
    FROM
        datalake_casa_mineira_crm_clean_prod.contact AS c
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.house AS h
            ON c.id_house = h.id
        LEFT JOIN datalake_casa_mineira_portal_clean_prod.house AS hp
            ON c.id_house = hp.code AND hp.id_real_estate_agency = '1'
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
        WHERE id_origin NOT IN ('12', '18', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30', '31', '32', '34', '35') AND id_origin::INT < 37
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
    NULL::TEXT AS id_visit,
    NULL::TEXT AS id_house_booked,
    NULL::TEXT AS id_client_booked,
    NULL::TEXT AS listing_type,
    NULL::TEXT AS uf_listing_booked,
    NULL::TEXT AS city_listing_booked,
    NULL::TEXT AS neighborhood_listing_booked,
    NULL::TEXT AS type_visit,
    NULL::INT AS order_new_visit_booked,
    0.0 AS cost,
    0.0 AS budget,
    0.0 AS new_contact_prospects_target,
    0.0 AS new_buyer_prospect_target
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
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27
),
contact_next AS (
    SELECT
        dt,
        DATE_ADD('DAY', -1, coalesce(LEAD(dt) OVER(partition by id_client order by dt), current_date)) as dt_next_contact,
        mkt_origin,
	    mkt_channel,
	    mkt_medium,
	    mkt_source,
	    id_client
    FROM
        results
),
visits AS (
    SELECT
        DATE(date_add('hour', 3, cmv.ts_created)) as dt,
        cn.mkt_origin,
        cn.mkt_channel,
        cn.mkt_medium,
        cn.mkt_source,
        NULL::TEXT AS utm_campaign,
        NULL::TEXT AS campaign_name,
        NULL::TEXT AS uf_listing,
        NULL::TEXT AS city_listing,
        NULL::TEXT AS neighborhood_listing,
        NULL::TEXT AS city_group,
        NULL::TEXT AS id_house,
        NULL::TEXT AS id_client,
        NULL::INT AS order_new_client,
        NULL::TEXT AS id_prospect,
        NULL::INT AS order_new_contact_prospect,
        NULL::TEXT AS id_flow,
        NULL::INT AS order_new_contact_flow,
        cmv.id AS id_visit,
        cmv.id_house AS id_house_booked,
        cmv.id_client AS id_client_booked,
        cmht.house_type_name AS listing_type,
        uf.uf_name AS uf_listing_booked,
        cmc.city_name AS city_listing_booked,
        cmn.neighborhood_name AS neighborhood_listing_booked,
        CASE WHEN cmv.is_virtual = false THEN 'presential' ELSE 'virtual' END AS type_visit,
        ROW_NUMBER() OVER(PARTITION BY cmv.id_client ORDER BY cmv.ts_created) AS order_new_visit_booked,
        0.0 AS cost,
        0.0 AS budget,
        0.0 AS new_contact_prospects_target,
        0.0 AS new_buyer_prospect_target
    FROM datalake_casa_mineira_crm_clean_prod.visit AS cmv
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.house cmh on cmh.id = cmv.id_house
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.neighborhood cmn on cmn.id = cmh.id_neighborhood
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.city cmc on cmc.id = cmn.id_city
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.uf uf on uf.id = cmc.id_uf
        LEFT JOIN datalake_casa_mineira_crm_clean_prod.house_type cmht on cmht.id = cmh.id_type
        LEFT JOIN contact_next AS cn ON cn.id_client = cmv.id_client AND DATE(cmv.ts_created) between cn.dt and cn.dt_next_contact
    WHERE
        DATE(date_add('hour', 3, cmv.ts_created)) BETWEEN DATE_ADD('YEAR', -1, CURRENT_DATE) AND DATE_ADD('DAY', -1, CURRENT_DATE)
),
---------------------------------
--- Query Targets from Sheets ---
---------------------------------
targets AS (
SELECT
    DATE(dt_target) dt,
    NULL::TEXT AS mkt_origin,
    CASE
        WHEN mkt_channel='Paid' THEN 'Paid Acquisition'
        ELSE mkt_channel
    END AS mkt_channel,
    mkt_medium,
    mkt_source,
    NULL::TEXT AS utm_campaign,
    NULL::TEXT AS campaign_name,
    NULL::TEXT AS uf_listing,
    NULL::TEXT AS city_listing,
    NULL::TEXT AS neighborhood_listing,
    city_group,
    NULL::TEXT AS id_house,
    NULL::TEXT AS id_client,
    NULL::INT AS order_new_client,
    NULL::TEXT AS id_prospect,
    NULL::INT AS order_new_contact_prospect,
    NULL::TEXT AS id_flow,
    NULL::INT AS order_new_contact_flow,
    NULL::TEXT AS id_visit,
    NULL::TEXT AS id_house_booked,
    NULL::TEXT AS id_client_booked,
    NULL::TEXT AS listing_type,
    NULL::TEXT AS uf_listing_booked,
    NULL::TEXT AS city_listing_booked,
    NULL::TEXT AS neighborhood_listing_booked,
    NULL::TEXT AS type_visit,
    NULL::INT AS order_new_visit_booked,
    0.0 AS cost,
    0.0 AS budget,
    SUM(ncp_target) AS new_contact_prospects_target,
    0.0 AS new_buyer_prospect_target
FROM
    datalake_gsheets_clean_prod.targets_casa_mineira_ncp
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27

UNION ALL

SELECT
    DATE(dt_target) dt,
    NULL::TEXT AS mkt_origin,
    CASE
        WHEN mkt_channel='Paid' THEN 'Paid Acquisition'
        ELSE mkt_channel
    END AS mkt_channel,
    mkt_medium,
    mkt_source,
    NULL::TEXT AS utm_campaign,
    NULL::TEXT AS campaign_name,
    NULL::TEXT AS uf_listing,
    NULL::TEXT AS city_listing,
    NULL::TEXT AS neighborhood_listing,
    city_group,
    NULL::TEXT AS id_house,
    NULL::TEXT AS id_client,
    NULL::INT AS order_new_client,
    NULL::TEXT AS id_prospect,
    NULL::INT AS order_new_contact_prospect,
    NULL::TEXT AS id_flow,
    NULL::INT AS order_new_contact_flow,
    NULL::TEXT AS id_visit,
    NULL::TEXT AS id_house_booked,
    NULL::TEXT AS id_client_booked,
    NULL::TEXT AS listing_type,
    NULL::TEXT AS uf_listing_booked,
    NULL::TEXT AS city_listing_booked,
    NULL::TEXT AS neighborhood_listing_booked,
    NULL::TEXT AS type_visit,
    NULL::INT AS order_new_visit_booked,
    0.0 AS cost,
    SUM(cost_target) AS budget,
    0.0 AS new_contact_prospects_target,
    0.0 AS new_buyer_prospect_target
FROM
    datalake_gsheets_clean_prod.targets_casa_mineira_cost
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27

UNION ALL

SELECT
    DATE(dt_target) dt,
    NULL::TEXT AS mkt_origin,
    CASE
        WHEN mkt_channel='Paid' THEN 'Paid Acquisition'
        ELSE mkt_channel
    END AS mkt_channel,
    mkt_medium,
    mkt_source,
    NULL::TEXT AS utm_campaign,
    NULL::TEXT AS campaign_name,
    NULL::TEXT AS uf_listing,
    NULL::TEXT AS city_listing,
    NULL::TEXT AS neighborhood_listing,
    city_group,
    NULL::TEXT AS id_house,
    NULL::TEXT AS id_client,
    NULL::INT AS order_new_client,
    NULL::TEXT AS id_prospect,
    NULL::INT AS order_new_contact_prospect,
    NULL::TEXT AS id_flow,
    NULL::INT AS order_new_contact_flow,
    NULL::TEXT AS id_visit,
    NULL::TEXT AS id_house_booked,
    NULL::TEXT AS id_client_booked,
    NULL::TEXT AS listing_type,
    NULL::TEXT AS uf_listing_booked,
    NULL::TEXT AS city_listing_booked,
    NULL::TEXT AS neighborhood_listing_booked,
    NULL::TEXT AS type_visit,
    NULL::INT AS order_new_visit_booked,
    0.0 AS cost,
    0.0 AS budget,
    0.0 AS new_contact_prospects_target,
    SUM(nbp_target) AS new_buyer_prospect_target
FROM
    datalake_gsheets_clean_prod.targets_casa_mineira_nbp
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27
)
--------------------------------------
-- UNION Costs, Results and Targets --
--------------------------------------
SELECT
    r.*
FROM
    results AS r

UNION ALL

SELECT
    v.*
FROM
    visits AS v

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