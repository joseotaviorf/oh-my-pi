WITH
-----------------------------------------------------------
-- Query bookings, offers and talk to agent full history --
-----------------------------------------------------------
events AS (
    SELECT
        flrf.sk_client,
        flrf.sk_house_listing,
        db.id_property AS id_house,
        flrf.sk_region,
        db.mkt_origin,
        db.mkt_channel,
        db.mkt_medium,
        db.mkt_source,
        db.utm_medium,
        db.utm_source,
        db.utm_campaign,
        db.utm_term,
        db.utm_content,
        db.dt_created AS ts_event,
        'Booking' AS flow_event
    FROM
        fact_listing_rent_flows AS flrf
        JOIN dim_booking AS db
            USING(sk_booking)
    WHERE
        db.sk_booking > 0
        AND db.visit_intent = 'RENT'
        AND db.type = 'Visita'
        AND db.dt_created IS NOT NULL
--
    UNION ALL
--
    SELECT
        flrf.sk_client,
        flrf.sk_house_listing,
        o.id_property AS id_house,
        flrf.sk_region,
        o.mkt_origin,
        o.mkt_channel,
        o.mkt_medium,
        o.mkt_source,
        o.utm_medium,
        o.utm_source,
        o.utm_campaign,
        o.utm_term,
        o.utm_content,
        o.dt_first_sent AS ts_event,
        'Offer' AS flow_event
    FROM
        fact_listing_rent_flows AS flrf
        JOIN dim_offer AS o
            USING(sk_offer)
    WHERE
        o.sk_offer > 0
        AND o.dt_first_sent IS NOT NULL
--
    UNION ALL
--
    SELECT
        tenant_id::INT AS sk_client,
        tta.sk_house_listing::BIGINT,
        house_id::INT AS id_house,
        fhl.sk_region,
        tta.mkt_origin,
        tta.mkt_channel,
        tta.mkt_medium,
        tta.mkt_source,
        tta.utm_medium,
        tta.utm_source,
        tta.utm_campaign,
        tta.utm_term,
        tta.utm_content,
        tta.first_message_ts::timestamp AS ts_event,
        'Talk to Agent' AS flow_event
    FROM
        datamarts.talk_to_agent AS tta
        JOIN fact_house_listings AS fhl
            ON tta.sk_house_listing = fhl.sk_house_listing
    WHERE
        tta.business_context = 'RENT'
        AND tta.first_message_ts IS NOT NULL
)
----------------------------------------------------------------------------------------------------------------------
-- Merge activation events (offer, booking and talk to agent) and order them by user and rent_flows (user || house) --
----------------------------------------------------------------------------------------------------------------------
SELECT
    evt.ts_event,
    DATE(evt.ts_event) AS dt_event,
    evt.flow_event,
    evt.sk_client,
    evt.sk_house_listing,
    evt.id_house,
    evt.sk_client || '_' || evt.id_house AS sk_rf,
    evt.sk_region,
    evt.mkt_origin,
    evt.mkt_channel,
    evt.mkt_medium,
    evt.mkt_source,
    evt.utm_medium,
    evt.utm_source,
    evt.utm_campaign,
    evt.utm_term,
    evt.utm_content,
    ROW_NUMBER() OVER(PARTITION BY evt.sk_client, evt.id_house ORDER BY evt.ts_event) AS rent_flow_order,
    ROW_NUMBER() OVER(PARTITION BY evt.sk_client ORDER BY evt.ts_event) AS tenant_prospect_order
FROM
    events AS evt