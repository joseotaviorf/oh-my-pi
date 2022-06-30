-----------------------------------------------------------
-- Query bookings, offers and talk to agent full history --
-----------------------------------------------------------
WITH events AS (
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
        dw_public.fact_listing_rent_flows AS flrf
        JOIN dw_public.dim_booking AS db
            ON CAST(flrf.sk_booking AS BIGINT) = CAST(db.sk_booking AS BIGINT)
    WHERE
        CAST(db.sk_booking AS BIGINT) > 0
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
        dw_public.fact_listing_rent_flows AS flrf
        JOIN dw_public.dim_offer AS o
            ON CAST(flrf.sk_offer AS BIGINT) = CAST(o.sk_offer AS BIGINT)
    WHERE
        CAST(o.sk_offer AS BIGINT) > 0
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
        dw_datamarts.talk_to_agent AS tta
        JOIN dw_public.fact_house_listings AS fhl
            ON CAST(tta.sk_house_listing AS BIGINT) = CAST(fhl.sk_house_listing AS BIGINT)
    WHERE
        tta.business_context = 'RENT'
        AND tta.first_message_ts IS NOT NULL
)
----------------------------------------------------------------------------------------------------------------------
-- Merge activation events (offer, booking and talk to agent) and order them by user and rent_flows (user || house) --
----------------------------------------------------------------------------------------------------------------------
SELECT
    CAST(evt.ts_event AS TIMESTAMP) AS ts_event,
    CAST(evt.ts_event AS DATE) AS dt_event,
    CAST(evt.flow_event AS STRING) AS flow_event,
    CAST(evt.sk_client AS BIGINT) AS sk_client,
    CAST(evt.sk_house_listing AS BIGINT) AS sk_house_listing,
    CAST(evt.id_house AS BIGINT) AS id_house,
    CAST(evt.sk_client || '_' || evt.id_house AS STRING) AS sk_rf,
    CAST(evt.sk_region AS BIGINT) AS sk_region,
    CAST(evt.mkt_origin AS STRING) AS mkt_origin,
    CAST(evt.mkt_channel AS STRING) AS mkt_channel,
    CAST(evt.mkt_medium AS STRING) AS mkt_medium,
    CAST(evt.mkt_source AS STRING) AS mkt_source,
    CAST(evt.utm_medium AS STRING) AS utm_medium,
    CAST(evt.utm_source AS STRING) AS utm_source,
    CAST(evt.utm_campaign AS STRING) AS utm_campaign,
    CAST(evt.utm_term AS STRING) AS utm_term,
    CAST(evt.utm_content AS STRING) AS utm_content,
    CAST(ROW_NUMBER() OVER(PARTITION BY evt.sk_client, evt.id_house ORDER BY evt.ts_event) AS BIGINT) AS rent_flow_order,
    CAST(ROW_NUMBER() OVER(PARTITION BY evt.sk_client ORDER BY evt.ts_event) AS BIGINT) AS tenant_prospect_order
FROM
    events AS evt