WITH rent_demand_events AS (
    SELECT
        rde.id_agent AS id_user_agent,
        rde.id_offer,
        rde.id_tenant_prospect,
        rde.id_event_type,
        CASE
            WHEN rde.id_event_type = 3 THEN "OFFER_SUBMITTED"
            WHEN rde.id_event_type = 4 THEN "OFFER_ACCEPTED"
            WHEN rde.id_event_type = 5 THEN "EVALUATION_STARTED"
            WHEN rde.id_event_type = 7 THEN "DOCUMENT_SENT"
            WHEN rde.id_event_type = 8 THEN "CREDIT_APPROVED"
            WHEN rde.id_event_type = 9 THEN "CONTRACT_SIGNED"
        END AS event_type,
        MIN(rde.ts_event) AS ts_event,
        YEAR(MIN(rde.ts_event)) AS year,
        MONTH(MIN(rde.ts_event)) AS month,
        DAY(MIN(rde.ts_event)) AS day
    FROM
        datalake_rent_demand_events.rent_demand_events AS rde
    WHERE 
        rde.id_event_type IN (3, 4, 5, 7, 8, 9)
        AND rde.id_agent IS NOT NULL
        AND rde.id_offer IS NOT NULL
        AND DATE(rde.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY ALL
),
sale_offer_events AS (
    SELECT 
        soe.id_user_agent,
        soe.id_offer,
        soe.id_buyer,
        STACK(
            3,
            3, "OFFER_SUBMITTED", soe.ts_offer_created,
            4, "OFFER_ACCEPTED", soe.ts_accepted,
            9, "CONTRACT_SIGNED", soe.ts_signed
        ) AS (id_event_type, event_type, ts_event)
    FROM
        datalake_sale_offer_flows.sale_offer_flows AS soe
    WHERE
        soe.id_user_agent IS NOT NULL
        AND soe.id_offer IS NOT NULL
        AND GREATEST(soe.ts_offer_updated, soe.ts_offer_created, soe.ts_accepted, soe.ts_signed) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        -- This workaround is done to try to mitigate the problems of retroactive changes in Sale data, given that we do not have a safe column that indicates the record update.
),
union_events AS (
    SELECT 
        XXHASH64(soe.id_user_agent, soe.id_offer, soe.id_event_type) AS id_offer_event,
        soe.id_user_agent,
        soe.id_offer,
        soe.id_buyer AS id_lead,
        soe.id_event_type,
        soe.event_type,
        "SALE" AS business_context,
        soe.ts_event,
        YEAR(soe.ts_event) AS year,
        MONTH(soe.ts_event) AS month,
        DAY(soe.ts_event) AS day
    FROM
        sale_offer_events AS soe
    UNION
    SELECT 
        XXHASH64(rde.id_user_agent, rde.id_offer, rde.id_event_type) AS id_offer_event,
        rde.id_user_agent,
        rde.id_offer,
        rde.id_tenant_prospect AS id_lead,
        rde.id_event_type,
        rde.event_type,
        "RENT" AS business_context,
        rde.ts_event,
        rde.year,
        rde.month,
        rde.day
    FROM
        rent_demand_events AS rde
),
rent_flows_touchpoint AS (
    SELECT DISTINCT
        rf.id_offer,
        COALESCE(rf.first_touchpoint = "DIRECT", FALSE) AS has_direct_first_touchpoint
    FROM
        datalake_rent_flows.rent_flows AS rf
)
SELECT 
    ue.id_offer_event,
    ue.id_user_agent,
    u.id_agent,
    ue.id_offer,
    ue.id_lead,
    ue.id_event_type,
    ue.event_type,
    ue.business_context,
    rf.has_direct_first_touchpoint,
    ue.ts_event,
    ue.year,
    ue.month,
    ue.day
FROM
    union_events AS ue
LEFT JOIN
    rent_flows_touchpoint AS rf
        ON rf.id_offer = ue.id_offer
LEFT JOIN
    datalake_ebdb_user.user AS u
        ON u.id = ue.id_user_agent