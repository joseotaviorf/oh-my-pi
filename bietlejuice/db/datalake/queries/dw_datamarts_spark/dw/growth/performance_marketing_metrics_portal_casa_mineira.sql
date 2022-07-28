WITH
------------------------------
-- Query Casa Mineira Costs --
------------------------------
costs AS (
    SELECT
        TO_DATE(NULLIF(id_date, -1)::STRING, 'yyyyMMdd') AS dt,
        NULL::INT AS id_advertiser,
        NULL::STRING AS advertiser,
        NULL::STRING AS uf_advertiser,
        NULL::STRING AS city_advertiser,
        NULL::STRING AS type_advertiser,
        NULL::STRING AS business_context,
        NULL::STRING AS uf_listing,
        NULL::STRING AS city_listing,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        funnel_side AS mkt_business,
        city_group,
        NULL::STRING AS utm_campaign,
        campaign_name,
        NULL::INT AS order_new_contact_flow,
        NULL::INT AS order_new_contact_prospect,
        NULL::STRING AS id_house,
        NULL::STRING AS id_prospect,
        NULL::STRING AS contact_flow,
        NULL::FLOAT AS budget_advertiser,
        SUM(cost) AS cost,
        NULL::FLOAT AS budget,
        NULL::FLOAT AS contact_flow_target
    FROM datalake_casa_mineira_marketing_costs.daily_costs
    WHERE TO_DATE(NULLIF(id_date,-1)::STRING, 'yyyyMMdd') BETWEEN ADD_MONTHS(CURRENT_DATE, -12) AND DATE_ADD(CURRENT_DATE , -1)
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22
),
----------------------------------------------------
-- Query Taxonomy Portal Casa Mineira From Sheets --
----------------------------------------------------
taxonomy AS (
    SELECT
    id,
    app_type::STRING,
    utm_source::STRING,
    utm_medium::STRING,
    branded::STRING,
    mkt_category,
    mkt_flow,
    mkt_completion,
    mkt_channel::STRING,
    mkt_medium::STRING,
    mkt_origin::STRING,
    mkt_source::STRING,
    mkt_platform
  FROM
      datalake_gsheets_clean.taxonomy_portal_casa_mineira
),
---------------------------------
-- Query Events from Amplitude --
---------------------------------
info_events AS (
    SELECT
        ts_event,
        GET_JSON_OBJECT(event_properties, '$.email_md5') AS email_md5,
        GET_JSON_OBJECT(event_properties, '$.house_id') AS id_house,
        GET_JSON_OBJECT(user_properties, '$.utm_source') AS utm_source,
        GET_JSON_OBJECT(user_properties, '$.utm_medium') AS utm_medium,
        GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS utm_campaign,
        CASE
            WHEN UPPER(GET_JSON_OBJECT(user_properties, '$.utm_campaign')) LIKE '%BRANDED%'
                        AND UPPER(GET_JSON_OBJECT(user_properties, '$.utm_campaign')) NOT LIKE '%NON-BRANDED%'
              THEN 'Branded'
            ELSE 'Outro'
        END AS branded,
        GET_JSON_OBJECT(user_properties , '$.platform') AS app_type,
        ROW_NUMBER() OVER(PARTITION BY GET_JSON_OBJECT(event_properties, '$.email_md5'), GET_JSON_OBJECT(event_properties, '$.house_id') ORDER BY ts_event) AS rn
    FROM
        datalake_casa_mineira_amplitude_clean.329001_portal
    WHERE
        event_type = 'receive_information_clicked'
        AND DATE(ts_event) BETWEEN ADD_MONTHS(CURRENT_DATE, -12) AND CURRENT_DATE
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
        c.ts_created + INTERVAL 3 hours AS ts_contact, --INTO UTC--
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
    FROM datalake_casa_mineira_portal_clean.contact AS c
        LEFT JOIN datalake_casa_mineira_portal_clean.house AS h
            ON c.id_house = h.id
        LEFT JOIN datalake_casa_mineira_portal_clean.real_estate_agency AS rea
            ON h.id_real_estate_agency = rea.id
        LEFT JOIN datalake_casa_mineira_portal_clean.neighborhood AS n
            ON n.id = h.id_neighborhood
        LEFT JOIN datalake_casa_mineira_portal_clean.city AS ctl
            ON n.id_city = ctl.id
        LEFT JOIN datalake_casa_mineira_portal_clean.city AS cta
            ON rea.id_city = cta.id
        LEFT JOIN datalake_casa_mineira_portal_clean.uf AS ufl
            ON ctl.id_uf = ufl.id
        LEFT JOIN datalake_casa_mineira_portal_clean.uf AS ufa
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
    NULL::STRING AS campaign_name,
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
        AND ABS(BIGINT(TO_TIMESTAMP(ts_event)) - BIGINT(TO_TIMESTAMP(ts_contact))) <= 360
    LEFT JOIN taxonomy AS t
        ON LOWER(COALESCE(t.app_type, '')) = LOWER(COALESCE(evt.app_type, ''))
      and LOWER(COALESCE(t.utm_source, '')) = LOWER(COALESCE(evt.utm_source, ''))
      and LOWER(COALESCE(t.utm_medium, '')) = LOWER(COALESCE(evt.utm_medium, ''))
      and LOWER(COALESCE(t.branded, '')) = LOWER(COALESCE(evt.branded, ''))
WHERE DATE(c.ts_contact) BETWEEN ADD_MONTHS(CURRENT_DATE, -12) AND DATE_ADD(CURRENT_DATE, -1)
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22
),
-------------------------------------------------------------
-- Query targets from sheets and introduce NULLs for UNION --
-------------------------------------------------------------
targets AS (
    SELECT
        dt_target AS dt,
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
        NULL::STRING AS utm_campaign,
        NULL::STRING AS campaign_name,
        NULL::INT AS order_new_contact_flow,
        NULL::INT AS order_new_contact_prospect,
        NULL::STRING AS id_house,
        NULL::STRING AS id_prospect,
        NULL::STRING AS contact_flow,
        NULL::FLOAT AS budget_advertiser,
        NULL::FLOAT AS cost,
        SUM(cost_target) AS budget,
        SUM(contact_flow_target) AS contact_flow_target
    FROM datalake_gsheets_clean.targets_portal_casa_mineira_cost_cf
    WHERE dt_target BETWEEN ADD_MONTHS(CURRENT_DATE, -12) AND DATE_ADD(CURRENT_DATE, -1)
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22
),
aux_budget AS (
    SELECT
        dt_month_started AS dt_budget,
        sk_real_estate_agency AS advertiser_id,
        month_budget,
        LEAD(dt_month_started) OVER(PARTITION BY sk_real_estate_agency ORDER BY dt_month_started) AS dt_next_change
    FROM dw_casa_mineira_portal.fact_real_estate_budget_flows
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
        NULL::STRING AS utm_campaign,
        NULL::STRING AS campaign_name,
        NULL::BIGINT AS order_new_contact_flow,
        NULL::BIGINT AS order_new_contact_prospect,
        NULL::STRING AS id_house,
        NULL::STRING AS id_prospect,
        NULL::STRING AS contact_flow,
        month_budget / (DATEDIFF(dd.month_end, dd.month_start) + 1)::FLOAT AS budget_advertiser,
        NULL::FLOAT AS cost,
        NULL::FLOAT AS budget,
        NULL::FLOAT AS contact_flow_target
    FROM aux_budget AS ab
    JOIN dw_public.dim_date AS dd
        ON dd.date BETWEEN dt_budget AND COALESCE(dt_next_change, CURRENT_DATE) - 1
    LEFT JOIN dw_casa_mineira_portal.dim_real_estate_agency AS dre
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
