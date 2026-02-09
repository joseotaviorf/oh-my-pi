-----------------------------------------------------------------------------------------
-- The Sale Flow is defined by the events happened in the tuple buyer <> house.       ---
-- It can start with three possible events (BOOKING, TALK TO AGENT OR DIRECT OFFER)   ---
-----------------------------------------------------------------------------------------
-- Bookings and visits - first dates and counts
WITH sale_booking AS (
    SELECT
        CONCAT(b.id_visitor, '_',b.id_house) AS id_sale_flow,
        b.id_visitor AS id_buyer,
        b.id_house,
        MIN(b.ts_created) AS ts_first_booking_created,
        MIN(CASE WHEN b.is_visit_completed THEN b.ts_booking_utc END) AS ts_first_visit_completed,
        COUNT(DISTINCT b.id) AS nbr_bookings,
        COUNT(DISTINCT CASE WHEN b.is_visit_completed THEN b.id END) AS nbr_visits_completed
    FROM
        datalake_booking.booking AS b
    WHERE
        b.visit_intent = 'SALE'
        AND b.type = 'Visita'
    GROUP BY 1, 2, 3
),
notary AS (
    SELECT
        id_notary,
        id_sales_flow,
        status,
        DATE(ts_started) AS dt_started,
        DATE(ts_ended) AS dt_ended,
        DATE(ts_ended) AS dt_house_registry_ended,
        DATE(ts_buyer_received_keys) AS dt_buyer_received_keys
    FROM
        datalake_sales_flow_clean.notary
    QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY id_notary ORDER BY ts_updated DESC) = 1
),
-- Talk to agent events - first dates and counts
sale_talk_to_agent AS (
    SELECT
        CONCAT(evt.id_user,'_',evt.id_house) AS id_sale_flow,
        evt.id_user AS id_buyer,
        evt.id_house,
        MIN(CAST(evt.ts_event AS TIMESTAMP)) AS ts_first_tta_message_sent,
        COUNT(evt.ts_event) AS nbr_tta_messages
    FROM
        datalake_talk_to_agent.talk_to_agent_events AS evt
    JOIN
        datalake_ebdb_listing.listing_business_context AS lbc
            ON evt.id_house = lbc.id_house
    WHERE
        CAST(ts_event AS DATE) > DATE('2020-03-01') -- month_start of tta event
        AND evt.business_context = 'SALE'
        AND lbc.business_context = 'SALE'
        AND evt.id_house IS NOT NULL
        AND evt.id_user IS NOT NULL
    GROUP BY 1, 2, 3
),
-- Offer funnel events - first dates and counts
sale_offer AS (
    SELECT
        CONCAT(so.id_buyer, '_', so.id_house) AS id_sale_flow,
        so.id_buyer,
        so.id_house,
        MIN(so.ts_offer_submitted) AS ts_first_offer_submitted,
        MIN(so.ts_offer_accepted) AS dt_first_offer_accepted,
        MIN(so.ts_offer_dismissed) AS dt_first_offer_dismissed,
        MIN(so.ts_sale_agreement_created) AS dt_sale_agreement_created,
        MIN(so.ts_sale_agreement_signed) AS dt_sale_agreement_signed,
        MIN(so.ts_sale_agreement_canceled) AS dt_sale_agreement_cancelled,
        MIN(n.dt_house_registry_ended) AS dt_house_registry_ended,
        MAX(so.first_discount_proposed) AS max_discount_proposed,
        COUNT(DISTINCT so.id_offer) AS nbr_offers_submitted
    FROM
        datalake_sale_offer.sale_offer AS so
    LEFT JOIN
        notary AS n
            ON so.id_sales_flow = n.id_sales_flow
    WHERE
        CONCAT(so.id_buyer, '_', so.id_house) IS NOT NULL
    GROUP BY 1, 2, 3
),
current_region AS (
    SELECT
        id,
        id_region
    FROM
        datalake_ebdb_clean.house AS h
),
base AS (
    SELECT
        ha.id_user,
        ha.id_house,
        cr.id_region,
        FROM_UNIXTIME(ure.ts_revision/1000) AS first_update
    FROM
        datalake_ebdb_clean.house_aud AS ha
    LEFT JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON ha.rev = ure.id
    LEFT JOIN
        current_region AS cr
            ON ha.id_house = cr.id
    WHERE
        ha.id_user IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY ha.id_user, id_house ORDER BY FROM_UNIXTIME(ure.ts_revision/1000) ASC) = 1
),
h_with_lag AS (
    SELECT
        id_user,
        LAG(id_user,1) OVER (PARTITION BY id_house ORDER BY first_update) AS lag_id_user,
        id_house,
        first_update AS ts_first_day_as_seller,
        COALESCE(LEAD(first_update) OVER (PARTITION BY id_house ORDER BY first_update), CURRENT_TIMESTAMP()) AS ts_last_day_as_seller,
        id_region
    FROM
        base
),
ajusted_house AS (
    SELECT
        id_user,
        id_house,
        id_region,
        CASE
            WHEN lag_id_user IS NULL -- First seller
                -- Arbitrarily low timestamp before operations began, for every house to have an associated seller at any point
                -- (fixes problems caused by Casa Mineira historical migration)
                THEN '2010-01-01'::TIMESTAMP 
            ELSE CAST(ts_first_day_as_seller AS TIMESTAMP)
        END AS ts_first_day_as_seller,
        CAST(ts_last_day_as_seller AS TIMESTAMP) AS ts_last_day_as_seller
    FROM
        h_with_lag
    WHERE
        (id_user <> lag_id_user
        OR lag_id_user IS NULL)
),
sale_listing_status AS (
    SELECT
        *
    FROM
        datalake_sale_listings.sale_listing_status
    WHERE
        status_history = "PUBLISHED"
),
house_info AS (
    SELECT
        h.id_house AS id_house,
        h.id_user AS id_seller,
        h.id_region,
        ts_first_day_as_seller,
        ts_last_day_as_seller,
        sls.ts_first_publication AS ts_first_listing
    FROM
        ajusted_house AS h
    LEFT JOIN
        sale_listing_status AS sls
            ON sls.id_house = h.id_house
            AND sls.id_region = h.id_region
            AND sls.ts_status_started BETWEEN ts_first_day_as_seller AND ts_last_day_as_seller
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY h.id_house, h.id_user ORDER BY sls.ts_status_started ASC) = 1
),
sale_flows AS (
SELECT
    COALESCE(b.id_sale_flow, o.id_sale_flow, tta.id_sale_flow) AS id_sale_flow,
    CAST(COALESCE(b.id_buyer, o.id_buyer, tta.id_buyer) AS BIGINT) AS id_buyer,
    CAST(COALESCE(b.id_house, o.id_house, tta.id_house) AS BIGINT)  AS id_house,
    CASE
        WHEN LEAST(b.ts_first_booking_created,o.ts_first_offer_submitted, tta.ts_first_tta_message_sent) = b.ts_first_booking_created
            THEN 'booking'
        WHEN LEAST(b.ts_first_booking_created,o.ts_first_offer_submitted, tta.ts_first_tta_message_sent) = o.ts_first_offer_submitted
            THEN 'offer'
        WHEN LEAST(b.ts_first_booking_created,o.ts_first_offer_submitted, tta.ts_first_tta_message_sent) = tta.ts_first_tta_message_sent
            THEN 'talk_to_agent'
        ELSE null
    END AS first_event,
    LEAST(b.ts_first_booking_created,o.ts_first_offer_submitted, tta.ts_first_tta_message_sent) AS ts_first_event,
    ROW_NUMBER() OVER (PARTITION BY COALESCE(b.id_buyer, o.id_buyer, tta.id_buyer) ORDER BY LEAST(b.ts_first_booking_created,o.ts_first_offer_submitted, tta.ts_first_tta_message_sent)) AS rank_buyer_sale_flow,
    ROW_NUMBER() OVER (PARTITION BY COALESCE(b.id_house, o.id_house, tta.id_house) ORDER BY LEAST(b.ts_first_booking_created,o.ts_first_offer_submitted, tta.ts_first_tta_message_sent)) AS rank_house_sale_flow
FROM
    sale_booking AS b
FULL OUTER JOIN
    sale_offer AS o
    ON b.id_sale_flow = o.id_sale_flow
FULL OUTER JOIN
    sale_talk_to_agent AS tta
    ON COALESCE(b.id_sale_flow, o.id_sale_flow) = tta.id_sale_flow
)
SELECT/*RANGE_JOIN(hi, 1000)*/
    sf.id_sale_flow,
    sf.id_buyer,
    sf.id_house,
    hi.id_seller,
    hi.id_region,
    sf.first_event,
    -- gets the higher intent before the offer submission (VC > VB > TTA > DO)
    CASE
        WHEN o.ts_first_offer_submitted IS NULL
            THEN null
        WHEN o.ts_first_offer_submitted >= b.ts_first_visit_completed AND b.ts_first_visit_completed IS NOT NULL
            THEN 'VC_before_OS'
        WHEN o.ts_first_offer_submitted >= b.ts_first_booking_created AND b.ts_first_booking_created IS NOT NULL
            THEN 'VB_before_OS'
        WHEN o.ts_first_offer_submitted >= tta.ts_first_tta_message_sent AND tta.ts_first_tta_message_sent IS NOT NULL
            THEN 'TTA_before_OS'
        ELSE 'Direct_Offer'
    END AS higher_intent_before_offer,
    --   gets the higher intent after the offer submission (VC > VB > TTA > DO)
    CASE
        WHEN o.ts_first_offer_submitted IS NULL
            THEN null
        WHEN o.ts_first_offer_submitted < b.ts_first_visit_completed
            THEN 'VC_after_OS'
        WHEN o.ts_first_offer_submitted < b.ts_first_booking_created
            THEN 'VB_after_OS'
        WHEN o.ts_first_offer_submitted < tta.ts_first_tta_message_sent
            THEN 'TTA_after_OS'
        ELSE 'only_Offer'
    END AS higher_intent_after_offer,
    sf.rank_buyer_sale_flow,
    sf.rank_house_sale_flow,
    sf.rank_buyer_sale_flow = 1 AS is_buyer_first_sale_flow,
    sf.rank_house_sale_flow = 1 AS is_house_first_sale_flow,
    -- which events happened in this sale flow
    CASE
        WHEN b.ts_first_booking_created IS NOT NULL AND b.ts_first_visit_completed IS NOT NULL AND tta.ts_first_tta_message_sent IS NOT NULL AND o.ts_first_offer_submitted IS NOT NULL
            THEN 'VB_VC_TTA_OS'
        WHEN b.ts_first_booking_created IS NOT NULL AND b.ts_first_visit_completed IS NOT NULL AND tta.ts_first_tta_message_sent IS NOT NULL AND o.ts_first_offer_submitted IS NULL
            THEN 'VB_VC_TTA'
        WHEN b.ts_first_booking_created IS NOT NULL AND b.ts_first_visit_completed IS NOT NULL AND tta.ts_first_tta_message_sent IS NULL AND o.ts_first_offer_submitted IS NOT NULL
            THEN 'VB_VC_OS'
        WHEN b.ts_first_booking_created IS NOT NULL AND b.ts_first_visit_completed IS NULL AND tta.ts_first_tta_message_sent IS NOT NULL AND o.ts_first_offer_submitted IS NOT NULL
            THEN 'VB_TTA_OS'
        WHEN b.ts_first_booking_created IS NOT NULL AND b.ts_first_visit_completed IS NOT NULL AND tta.ts_first_tta_message_sent IS NULL AND o.ts_first_offer_submitted IS NULL
            THEN 'VB_VC'
        WHEN b.ts_first_booking_created IS NOT NULL AND b.ts_first_visit_completed IS NULL AND tta.ts_first_tta_message_sent IS NULL AND o.ts_first_offer_submitted IS NOT NULL
            THEN 'VB_OS'
        WHEN b.ts_first_booking_created IS NOT NULL AND b.ts_first_visit_completed IS NULL AND tta.ts_first_tta_message_sent IS NOT NULL AND o.ts_first_offer_submitted IS NULL
            THEN 'VB_TTA'
        WHEN b.ts_first_booking_created IS NOT NULL AND b.ts_first_visit_completed IS NULL AND tta.ts_first_tta_message_sent IS NULL AND o.ts_first_offer_submitted IS NULL
            THEN 'VB'
        WHEN b.ts_first_booking_created IS NULL AND b.ts_first_visit_completed IS NULL AND tta.ts_first_tta_message_sent IS NOT NULL AND o.ts_first_offer_submitted IS NOT NULL
            THEN 'TTA_OS'
        WHEN b.ts_first_booking_created IS NULL AND b.ts_first_visit_completed IS NULL AND tta.ts_first_tta_message_sent IS NOT NULL AND o.ts_first_offer_submitted IS NULL
            THEN 'TTA'
        WHEN b.ts_first_booking_created IS NULL AND b.ts_first_visit_completed IS NULL AND tta.ts_first_tta_message_sent IS NULL AND o.ts_first_offer_submitted IS NOT NULL
            THEN 'OS'
        ELSE NULL
    END AS flow_type,
    max_discount_proposed,
    COALESCE(b.nbr_bookings,0) AS bookings,
    COALESCE(b.nbr_visits_completed,0) AS visits_completed,
    COALESCE(o.nbr_offers_submitted,0) AS offers_submitted,
    COALESCE(tta.nbr_tta_messages,0) AS tta_messages_sent,
    DATEDIFF(sf.ts_first_event, hi.ts_first_listing) AS days_first_publication_to_first_event,
    DATEDIFF(b.ts_first_booking_created, hi.ts_first_listing) AS days_first_publication_to_first_booking_created,
    DATEDIFF(b.ts_first_visit_completed, hi.ts_first_listing) AS days_first_publication_to_first_visit_completed,
    DATEDIFF(o.ts_first_offer_submitted, hi.ts_first_listing) AS days_first_publication_to_first_offer_submitted,
    DATEDIFF(o.dt_first_offer_accepted, hi.ts_first_listing) AS days_first_publication_to_first_offer_accepted,
    DATEDIFF(o.dt_sale_agreement_signed, hi.ts_first_listing) AS days_first_publication_to_sale_agreement_signed,
    DATEDIFF(o.dt_house_registry_ended, hi.ts_first_listing) AS days_first_publication_to_house_registry_ended,
    DATEDIFF(b.ts_first_visit_completed, sf.ts_first_event) AS days_first_event_to_first_visit_completed,
    DATEDIFF(o.ts_first_offer_submitted, sf.ts_first_event) AS days_first_event_to_first_offer_submitted,
    DATEDIFF(o.dt_first_offer_accepted, sf.ts_first_event) AS days_first_event_to_first_offer_accepted,
    DATEDIFF(o.dt_sale_agreement_signed, sf.ts_first_event) AS days_first_event_to_sale_agreement_signed,
    DATEDIFF(o.dt_house_registry_ended, sf.ts_first_event) AS days_first_event_to_house_registry_ended,
    DATEDIFF(b.ts_first_visit_completed, b.ts_first_booking_created) AS days_first_booking_created_to_first_visit_completed,
    DATEDIFF(o.ts_first_offer_submitted, b.ts_first_booking_created) AS days_first_booking_created_to_first_offer_submitted,
    DATEDIFF(o.dt_first_offer_accepted, b.ts_first_booking_created) AS days_first_booking_created_to_first_offer_accepted,
    DATEDIFF(o.dt_sale_agreement_signed, b.ts_first_booking_created) AS days_first_booking_created_to_sale_agreement_signed,
    DATEDIFF(o.dt_house_registry_ended, b.ts_first_booking_created) AS days_first_booking_created_to_house_registry_ended,
    DATEDIFF(o.ts_first_offer_submitted, b.ts_first_visit_completed) AS days_first_visit_completed_to_first_offer_submitted,
    DATEDIFF(o.dt_first_offer_accepted, b.ts_first_visit_completed) AS days_first_visit_completed_to_first_offer_accepted,
    DATEDIFF(o.dt_sale_agreement_signed, b.ts_first_visit_completed) AS days_first_visit_completed_to_sale_agreement_signed,
    DATEDIFF(o.dt_house_registry_ended, b.ts_first_visit_completed) AS days_first_visit_completed_to_house_registry_ended,
    DATEDIFF(o.dt_first_offer_accepted, o.ts_first_offer_submitted) AS days_first_offer_submitted_to_first_offer_accepted,
    DATEDIFF(o.dt_sale_agreement_signed, o.ts_first_offer_submitted) AS days_first_offer_submitted_to_sale_agreement_signed,
    DATEDIFF(o.dt_sale_agreement_signed, o.dt_first_offer_accepted) AS days_first_offer_accepted_to_sale_agreement_signed,
    DATEDIFF(o.dt_house_registry_ended, o.ts_first_offer_submitted) AS days_first_offer_submitted_to_house_registry_ended,
    hi.ts_first_listing,
    sf.ts_first_event,
    tta.ts_first_tta_message_sent,
    b.ts_first_booking_created,
    b.ts_first_visit_completed,
    o.ts_first_offer_submitted,
    o.dt_first_offer_accepted,
    o.dt_first_offer_dismissed,
    o.dt_sale_agreement_created,
    o.dt_sale_agreement_signed,
    o.dt_sale_agreement_cancelled,
    o.dt_house_registry_ended
FROM
    sale_flows AS sf
LEFT JOIN
    house_info AS hi
        ON hi.id_house = sf.id_house
        AND sf.ts_first_event BETWEEN hi.ts_first_day_as_seller AND hi.ts_last_day_as_seller
LEFT JOIN
    sale_booking AS b
        ON b.id_sale_flow = sf.id_sale_flow
LEFT JOIN
    sale_offer AS o
        ON o.id_sale_flow = sf.id_sale_flow
LEFT JOIN
    sale_talk_to_agent AS tta
        ON tta.id_sale_flow = sf.id_sale_flow
WHERE
    sf.id_buyer != hi.id_seller
