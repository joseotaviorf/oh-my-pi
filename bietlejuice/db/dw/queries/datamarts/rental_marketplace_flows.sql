WITH
----------------------------------
-- All Listing Flows base query --
----------------------------------
all_listings AS (
    SELECT 
        f.sk_house_listing,
        f.status_history,
        CASE
            WHEN status_history NOT IN ('alugado', 'despublicado', 'suspenso', 'publicado')
                THEN 'outros'
            ELSE status_history
        END AS status_history_v2,
        CASE
            WHEN status_history = 'despublicado' AND (LOWER(status_change_reason) LIKE '%rescisao%' OR LOWER(status_change_reason) LIKE '%rescisão%')
                THEN 'ended_rental'
            WHEN status_history = 'despublicado' AND (LOWER(status_change_reason) LIKE '%contato%' OR LOWER(status_change_reason) LIKE '%não atende%')
                THEN 'no_contact'
            WHEN status_history = 'despublicado' AND LOWER(status_change_reason) LIKE '%vend%' 
                THEN 'sale'
            WHEN status_history = 'despublicado' AND (LOWER(status_change_reason) LIKE '%modelo de negócio%' OR LOWER(status_change_reason) LIKE       '%administração%')
                THEN 'business_model'
            WHEN status_history = 'despublicado' AND LOWER(status_change_reason) LIKE '%gestão%' 
                THEN 'consequence_mngmt'
            WHEN status_history = 'despublicado' AND (LOWER(status_change_reason) LIKE '%locou%' OR LOWER(status_change_reason) LIKE '%alugou%')
                THEN 'rented_elsewhere'
            WHEN status_history = 'suspenso' AND LOWER(status_change_reason) LIKE '%reservado%'
                THEN 'reservation'
            WHEN status_history = 'suspenso' AND LOWER(status_change_reason) LIKE '%minuta%'
                THEN 'minuta'
            WHEN status_history = 'suspenso' AND LOWER(status_change_reason) LIKE '%pelo proprietário%'
                THEN 'by_owner'
            WHEN status_history = 'suspenso' AND LOWER(status_change_reason) LIKE '%gestão%'
                THEN 'consequence_mngmt'
            WHEN (LOWER(status_change_reason) LIKE '%reserv%' OR LOWER(status_change_reason) LIKE '%negocia%' OR LOWER(status_change_reason) LIKE       '%proposta%')
                THEN 'suspended_in_negotiation'
            ELSE NULL
        END AS status_change_reason,
        DATE(f.ts_status_start) AS dt_status_start,
        DATE(COALESCE(f.ts_status_end, CURRENT_DATE)) AS dt_status_end,
        f.ts_status_start
    FROM 
        fact_house_listing_status AS f
        INNER JOIN dim_house_listing AS dhl
            ON dhl.sk_house_listing = f.sk_house_listing
    WHERE
        dhl.version > 0
),
all_listings_date AS (
    SELECT DISTINCT
        al.sk_house_listing,
        al.status_history_v2,
        al.status_change_reason,
        d.week_start,
        al.ts_status_start,
        MAX(al.ts_status_start) OVER(
            PARTITION BY al.sk_house_listing, d.week_start
        ) AS last_status_start
    FROM
        dim_date AS d
        JOIN all_listings AS al
            ON d.date >= al.dt_status_start
            AND d.date < al.dt_status_end
    WHERE
        d.week_start < DATE_TRUNC('week', CURRENT_DATE)
        AND d.week_start >= DATE('2019-12-30')
),
al_week AS (
    SELECT
        aldr.sk_house_listing,
        aldr.status_history_v2 AS status_history,
        aldr.status_change_reason,
        aldr.week_start,
        DATE(DATEADD(WEEK, 1, aldr.week_start)) AS next_week_start
    FROM
        all_listings_date AS aldr
    WHERE
        last_status_start = ts_status_start
), 
al_week_status AS (
    SELECT
        COALESCE(alm_ms.sk_house_listing, alm_nms.sk_house_listing) AS sk_house_listing,
        alm_ms.status_history AS status_week_start,
        alm_nms.status_history AS status_next_week,
        alm_ms.status_change_reason,
        alm_nms.status_change_reason AS next_status_change_reason,
        COALESCE(alm_ms.week_start, (DATEADD(WEEK, -1, COALESCE(alm_ms.next_week_start, alm_nms.week_start))))::DATE AS week_start,
        COALESCE(alm_ms.next_week_start, alm_nms.week_start) AS next_week_start
    FROM al_week AS alm_ms
        FULL OUTER JOIN al_week AS alm_nms
            ON alm_ms.sk_house_listing = alm_nms.sk_house_listing
            AND alm_ms.next_week_start = alm_nms.week_start
),
al_week_status_region AS (
    SELECT
        alm.sk_house_listing,
        fhl.sk_region,
        alm.status_week_start,
        alm.status_next_week,
        alm.status_change_reason,
        alm.next_status_change_reason,
        alm.week_start,
        alm.next_week_start
    FROM al_week_status AS alm
        LEFT JOIN fact_house_listings AS fhl
            ON alm.sk_house_listing = fhl.sk_house_listing
        LEFT JOIN dim_region AS dr
            ON fhl.sk_region = dr.sk_region
    WHERE
        dr.city_group IS NOT NULL
),
--------------------------------------
-- Summarize listings weekly status --
--------------------------------------
weekly_listings_status AS (
    SELECT DISTINCT
        week_start,
        sk_house_listing,
        sk_region,
        CASE
            WHEN  COALESCE(status_week_start, '') = 'publicado'
                THEN 'Ongoing Listing'
            WHEN COALESCE(status_week_start, '') = ''
                THEN 'New Listing'
            WHEN  COALESCE(status_week_start, '') NOT IN ('publicado','alugado','') AND COALESCE(status_change_reason, '') IN ('suspended_in_negotiation', 'minuta', 'reservation')
                THEN 'Advanced Negociation'
            WHEN week_start < DATEADD('WEEK', -1, DATE_TRUNC('WEEK', CURRENT_DATE))
                THEN 'Other'
            ELSE NULL
        END AS status_short,
        CASE
            WHEN COALESCE(status_next_week, '') = 'publicado'
                THEN 'Ongoing Listing'
            WHEN COALESCE(status_next_week, '') = 'alugado'
                THEN 'Rented'
            WHEN COALESCE(status_next_week, '') NOT IN ('publicado', 'alugado') AND COALESCE(next_status_change_reason, '') IN ('suspended_in_negotiation', 'minuta', 'reservation')
                THEN 'Advanced Negociation'
            WHEN week_start < DATEADD('WEEK', -1, DATE_TRUNC('WEEK', CURRENT_DATE))
                THEN 'Other'
            ELSE NULL
        END AS status_next_week_short
    FROM
        al_week_status_region AS alm
    WHERE
        week_start < DATE_TRUNC('WEEK', CURRENT_DATE)
        AND NOT (status_short = 'Other' AND status_next_week_short = 'Other')
),
---------------------------------------------------------------------------------------------------
-- Query Bottom Demand Funnel in listing and client grain and Cummulative Rent Flows per Listing --
---------------------------------------------------------------------------------------------------
rent_flow_interactions AS (
    SELECT
        rfi.dt_event,
        dr.city_group,
        rfi.sk_house_listing,
        rfi.sk_region,
        rfi.sk_client,
        rfi.sk_rf
    FROM
        datamarts.rent_flow_interactions AS rfi
        JOIN dim_region AS dr
            USING(sk_region)
    WHERE
        rfi.rent_flow_order = 1
),
demand_funnel AS (
----------------
-- RENT FLOWS --
----------------
    SELECT
        dd.week_start,
        sk_region,
        sk_client,
        sk_house_listing,
        COUNT(DISTINCT sk_rf) AS rent_flows,
        SUM(rent_flows) OVER(
            PARTITION BY sk_house_listing
            ORDER BY week_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cum_rent_flows,
        COUNT(NULL) AS visits_booked,
        COUNT(NULL) AS offers_submitted,
        COUNT(NULL) AS offers_accepted,
        COUNT(NULL) AS credits_approved,
        COUNT(NULL) AS contracts_signed
    FROM
        rent_flow_interactions AS rf
        JOIN dim_date AS dd
          ON dd.date = rf.dt_event
    GROUP BY 1,2,3,4
    --
    UNION ALL
    --
--------------
-- BOOKINGS --
--------------
    SELECT
        dd.week_start,
        sk_region,
        sk_client,
        sk_house_listing,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS cum_rent_flows,
        COUNT(DISTINCT sk_booking) AS visits_booked,
        COUNT(NULL) AS offers_submitted,
        COUNT(NULL) AS offers_accepted,
        COUNT(NULL) AS credits_approved,
        COUNT(NULL) AS contracts_signed
    FROM
        fact_listing_rent_flows AS flrf
        JOIN dim_booking AS db
            USING(sk_booking)
        JOIN dim_date AS dd
            ON dd.sk_date = flrf.sk_booking_created_date
    WHERE
        db.sk_booking > 0
        AND dd.date >= DATE('2019-12-30')
    GROUP BY 1,2,3,4
    --
    UNION ALL
    --
----------------------
-- OFFERS SUBMITTED --
----------------------
    SELECT
        dd.week_start,
        sk_region,
        sk_client,
        sk_house_listing,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS cum_rent_flows,
        COUNT(NULL) AS visits_booked,
        COUNT(DISTINCT sk_offer) AS offers_submitted,
        COUNT(NULL) AS offers_accepted,
        COUNT(NULL) AS credits_approved,
        COUNT(NULL) AS contracts_signed
    FROM
        fact_listing_rent_flows AS flrf
        JOIN dim_offer AS o
            USING(sk_offer)
        JOIN dim_date AS dd
            ON dd.sk_date = flrf.sk_offer_submitted_date
    WHERE
        o.sk_offer > 0
        AND dd.date >= DATE('2019-12-30')
    GROUP BY 1,2,3,4
    --
    UNION ALL
    --
---------------------
-- OFFERS ACCEPTED --
---------------------
    SELECT
        dd.week_start,
        sk_region,
        sk_client,
        sk_house_listing,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS cum_rent_flows,
        COUNT(NULL) AS visits_booked,
        COUNT(NULL) AS offers_submitted,
        COUNT(DISTINCT sk_offer) AS offers_accepted,
        COUNT(NULL) AS credits_approved,
        COUNT(NULL) AS contracts_signed
    FROM
        fact_listing_rent_flows AS flrf
        JOIN dim_offer AS o
            USING(sk_offer)
        JOIN dim_date AS dd
            ON dd.sk_date = flrf.sk_offer_approved_date
    WHERE
        o.sk_offer > 0
        AND dd.date >= DATE('2019-12-30')
    GROUP BY 1,2,3,4
    --
    UNION ALL
    --
----------------------
-- CREDITS APPROVED --
----------------------
    SELECT
        dd.week_start,
        sk_region,
        sk_client,
        sk_house_listing,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS cum_rent_flows,
        COUNT(NULL) AS visits_booked,
        COUNT(NULL) AS offers_submitted,
        COUNT(NULL) AS offers_accepted,
        COUNT(DISTINCT sk_proposal) AS credits_approved,
        COUNT(NULL) AS contracts_signed
    FROM
        fact_listing_rent_flows AS flrf
        JOIN dim_date AS dd
            ON dd.sk_date = flrf.sk_credit_analysis_approved_date
    WHERE
        flrf.sk_proposal > 0
        AND dd.date >= DATE('2019-12-30')
    GROUP BY 1,2,3,4
    --
    UNION ALL
    --
----------------------
-- CONTRACTS SIGNED --
----------------------
    SELECT
        dd.week_start,
        sk_region,
        sk_client,
        sk_house_listing,
        COUNT(NULL) AS rent_flows,
        COUNT(NULL) AS cum_rent_flows,
        COUNT(NULL) AS visits_booked,
        COUNT(NULL) AS offers_submitted,
        COUNT(NULL) AS offers_accepted,
        COUNT(NULL) AS credits_approved,
        COUNT(DISTINCT sk_contract) AS contracts_signed
    FROM
        fact_listing_rent_flows AS flrf
        JOIN dim_date AS dd
            ON dd.sk_date = flrf.sk_contract_signed_date
    WHERE
        flrf.sk_contract > 0
        AND dd.date >= DATE('2019-12-30')
    GROUP BY 1,2,3,4
),
listings_with_demand AS (
    SELECT
        week_start,
        sk_region,
        sk_house_listing,
        sk_client,
        cum_rent_flows,
        SUM(rent_flows) AS rent_flows,
        SUM(cum_rent_flows) AS cum_rent_flows,
        SUM(visits_booked) AS visits_booked,
        SUM(offers_submitted) AS offers_submitted,
        SUM(offers_accepted) AS offers_accepted,
        SUM(credits_approved) AS credits_approved,
        SUM(contracts_signed) AS contracts_signed,
        MAX(cum_rent_flows) OVER(
            PARTITION BY week_start, sk_house_listing
        ) AS listing_cummulative_rent_flows
    FROM
        demand_funnel AS df
    WHERE
        week_start >= DATE('2019-12-30')
    GROUP BY 1,2,3,4,5
),
---------------------------------------------------------------------------
-- Query Tenant Prospect Activation by each listing they have interacted --
---------------------------------------------------------------------------
tenant_prospect_interactions AS (
    SELECT DISTINCT
        dt_event,
        sk_region,
        city_group,
        sk_house_listing,
        sk_client
    FROM
        rent_flow_interactions
),
activation_periods AS (
    SELECT
        status,
        sk_client,
        city_group,
        ts_start,
        dd.date,
        dd.week_start
    FROM
        datamarts.tenant_prospect_status AS tps
        JOIN dim_date AS dd
            ON dd.sk_date BETWEEN sk_start_date
                                  AND COALESCE(sk_end_date::INT, TO_CHAR(CURRENT_DATE - 1, 'YYYYMMDD')::INT)
    WHERE
        status = 'ACTIVE'
        AND dd.week_start >= DATE('2019-12-30')
),
active_tp_interactions AS (
    SELECT DISTINCT
        ap.week_start,
        tpi.sk_region,
        tpi.sk_house_listing,
        tpi.sk_client
    FROM
        activation_periods AS ap
        LEFT JOIN tenant_prospect_interactions AS tpi
            ON ap.sk_client = tpi.sk_client
            AND ap.city_group = tpi.city_group
            AND DATEDIFF('DAY', tpi.dt_event, ap.date) BETWEEN 0 AND 35 --Tenant Prospects are considered "active" if their last rent flow occurred within 35 days
)
----------------------------------------------------
-- Join listing status with demand and active TPs --
----------------------------------------------------
SELECT DISTINCT
    COALESCE(wls.week_start, atp.week_start, lwd.week_start) AS week_start,
    COALESCE(wls.sk_region, atp.sk_region, lwd.sk_region) AS sk_region,
    COALESCE(wls.sk_house_listing, atp.sk_house_listing, lwd.sk_house_listing) AS sk_house_listing,
    COALESCE(atp.sk_client, lwd.sk_client) AS sk_client,
    MAX(listing_cummulative_rent_flows) OVER(
        PARTITION BY COALESCE(wls.sk_house_listing, atp.sk_house_listing, lwd.sk_house_listing)
        ORDER BY COALESCE(wls.week_start, atp.week_start, lwd.week_start) ASC, COALESCE(listing_cummulative_rent_flows, 0) DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS listing_cummulative_rent_flows,
    SUM(lwd.rent_flows) OVER(
        PARTITION BY COALESCE(wls.week_start, atp.week_start, lwd.week_start),
                     COALESCE(wls.sk_house_listing, atp.sk_house_listing, lwd.sk_house_listing)
    ) AS listing_weekly_rent_flows,
    status_short,
    status_next_week_short,
    CASE
        WHEN atp.sk_client > 0
            THEN TRUE
        ELSE FALSE
    END AS is_active_tp,
    CASE
        WHEN GREATEST(rent_flows, visits_booked, offers_submitted, offers_accepted, credits_approved, contracts_signed) > 0
            THEN TRUE
        ELSE FALSE
    END AS had_demand,
    COALESCE(lwd.rent_flows, 0) AS rent_flows,
    COALESCE(lwd.visits_booked, 0) AS visits_booked,
    COALESCE(lwd.offers_submitted, 0) AS offers_submitted,
    COALESCE(lwd.offers_accepted, 0) AS offers_accepted,
    COALESCE(lwd.credits_approved, 0) AS credits_approved,
    COALESCE(lwd.contracts_signed, 0) AS contracts_signed
FROM
    weekly_listings_status AS wls
    FULL OUTER JOIN active_tp_interactions AS atp
        ON wls.week_start = atp.week_start
        AND wls.sk_house_listing = atp.sk_house_listing
    FULL OUTER JOIN listings_with_demand AS lwd
        ON COALESCE(wls.week_start, atp.week_start) = lwd.week_start
        AND COALESCE(wls.sk_house_listing, atp.sk_house_listing) = lwd.sk_house_listing
        AND atp.sk_client = lwd.sk_client