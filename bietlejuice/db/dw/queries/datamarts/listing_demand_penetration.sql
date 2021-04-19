WITH
daily_published_listings AS (
    SELECT
        f.sk_house_listing,
        f.status_history,
        d.date,
        d.week_start,
        d.weekday_name,
        d.month_start,
        d.month_end,
        ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC) AS order_status -- daily order status
    FROM
        fact_house_listing_status AS f
        JOIN dim_date AS d
            ON d.sk_date BETWEEN
                NULLIF(f.sk_status_start_date, -1)
                AND COALESCE(TO_CHAR(TO_DATE(NULLIF(sk_status_end_date, -1), 'YYYYMMDD') - 1, 'YYYYMMDD')::BIGINT, TO_CHAR(CURRENT_DATE - 1, 'YYYYMMDD')::BIGINT)
    WHERE
        f.status_history = 'publicado' -- consider only published status
        AND SUBSTRING(sk_house_listing, 10, 12) <> '000' -- consider only listings that already started publication
),
daily_published_listings_adjusted AS (
    SELECT
        fhs.sk_house_listing,
        fhs.date,
        fhs.week_start,
        fhl.sk_region,
        dhl.house_bedrooms,
        dhl.house_type
    FROM
        daily_published_listings AS fhs
        LEFT JOIN fact_house_listings AS fhl
            ON fhs.sk_house_listing = fhl.sk_house_listing
        LEFT JOIN dim_house_listing AS dhl
            ON fhs.sk_house_listing = dhl.sk_house_listing
        LEFT JOIN dim_region AS dr
            ON fhl.sk_region = dr.sk_region
    WHERE
        fhs.order_status = 1
        AND dr.city_group IS NOT NULL
        AND fhs.weekday_name = 'Sunday' -- filter that indicates it will be grouped by week
),
ol_weekly AS (
    SELECT
        week_start,
        sk_region,
        house_bedrooms,
        house_type,
        COUNT(DISTINCT sk_house_listing)
    FROM
        daily_published_listings_adjusted
    GROUP BY 1,2,3,4
),
demand_funnel AS (
----------------
-- RENT FLOWS --
----------------
    SELECT
        dd.week_start,
        sk_region,
        sk_house_listing,
        COUNT(DISTINCT sk_rf) AS rent_flows,
        COUNT(NULL) AS visits_booked,
        COUNT(NULL) AS offers_submitted,
        COUNT(NULL) AS offers_accepted,
        COUNT(NULL) AS credits_approved,
        COUNT(NULL) AS contracts_signed
    FROM
        datamarts.rent_flow_interactions AS rfi
        JOIN dim_date AS dd
            ON dd.date = rfi.dt_event
    WHERE
        rent_flow_order = 1
    GROUP BY 1,2,3
    --
    UNION ALL
    --
--------------
-- BOOKINGS --
--------------
    SELECT
        dd.week_start,
        sk_region,
        sk_house_listing,
        COUNT(NULL) AS rent_flows,
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
    GROUP BY 1,2,3
    --
    UNION ALL
    --
----------------------
-- OFFERS SUBMITTED --
----------------------
    SELECT
        dd.week_start,
        sk_region,
        sk_house_listing,
        COUNT(NULL) AS rent_flows,
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
    GROUP BY 1,2,3
    --
    UNION ALL
    --
---------------------
-- OFFERS ACCEPTED --
---------------------
    SELECT
        dd.week_start,
        sk_region,
        sk_house_listing,
        COUNT(NULL) AS rent_flows,
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
    GROUP BY 1,2,3
    --
    UNION ALL
    --
----------------------
-- CREDITS APPROVED --
----------------------
    SELECT
        dd.week_start,
        sk_region,
        sk_house_listing,
        COUNT(NULL) AS rent_flows,
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
    GROUP BY 1,2,3
    --
    UNION ALL
    --
----------------------
-- CONTRACTS SIGNED --
----------------------
    SELECT
        dd.week_start,
        sk_region,
        sk_house_listing,
        COUNT(NULL) AS rent_flows,
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
    GROUP BY 1,2,3
),
listings_with_demand AS (
    SELECT
        week_start,
        sk_region,
        sk_house_listing,
        house_bedrooms,
        house_type,
        SUM(rent_flows) AS rent_flows,
        SUM(visits_booked) AS visits_booked,
        SUM(offers_submitted) AS offers_submitted,
        SUM(offers_accepted) AS offers_accepted,
        SUM(credits_approved) AS credits_approved,
        SUM(contracts_signed) AS contracts_signed
    FROM
        demand_funnel AS df
        JOIN dim_house_listing AS dhl
            USING(sk_house_listing)
    GROUP BY 1,2,3,4,5
)
SELECT DISTINCT
    COALESCE(dpla.week_start, lwd.week_start) AS week_start,
    COALESCE(dpla.sk_region, lwd.sk_region) AS sk_region,
    COALESCE(dpla.sk_house_listing, lwd.sk_house_listing) AS sk_house_listing,
    COALESCE(dpla.house_bedrooms, lwd.house_bedrooms) AS house_bedrooms,
    COALESCE(dpla.house_type, lwd.house_type) AS house_type,
    CASE
        WHEN dpla.sk_house_listing > 0
            THEN TRUE
        ELSE FALSE
    END AS is_ongoing_listing,
    CASE
		WHEN GREATEST(rent_flows, visits_booked, offers_submitted, offers_accepted, credits_approved, contracts_signed) > 0
            THEN TRUE
        ELSE FALSE
    END AS had_demand,
    COALESCE(rent_flows, 0) AS rent_flows,
    COALESCE(visits_booked, 0) AS visits_booked,
    COALESCE(offers_submitted, 0) AS offers_submitted,
    COALESCE(offers_accepted, 0) AS offers_accepted,
    COALESCE(credits_approved, 0) AS credits_approved,
    COALESCE(contracts_signed, 0) AS contracts_signed
FROM
    daily_published_listings_adjusted AS dpla
    FULL OUTER JOIN listings_with_demand AS lwd
        ON dpla.week_start = lwd.week_start
        AND dpla.sk_house_listing = lwd.sk_house_listing