WITH
----------------------------------
-- All Rent Flows base query --
----------------------------------
rent_flows AS (
    SELECT
        f.week_start,
        dr.macro_id,
        f.sk_house_listing,
        f.status_short,
        f.had_demand,
        SUM(f.rent_flows) AS rent_flows
    FROM
        datamarts.rental_marketplace_flows f
    LEFT JOIN
        dim_region dr
         ON dr.sk_region = f.sk_region
    WHERE
        f.week_start >= '2019-01-01'
    GROUP BY 1, 2, 3, 4, 5
),
---------------------------------------------
-- All listing page view events base query --
---------------------------------------------
lpv AS (
    SELECT
        DATE_TRUNC('week', lpv.ts_event) AS event_week,
        lpv.id_house,
        dr.macro_id,
        COUNT(CONCAT(lpv.id_amplitude, lpv.id_session)) AS lpv_events
    FROM
        datalake_amplitude_page_viewed_events_prod.listing_page_viewed lpv
    JOIN
        fact_house_listings fhl
         ON LEFT(fhl.sk_house_listing,9) = lpv.id_house
    LEFT JOIN
        dim_region dr
         ON dr.sk_region = fhl.sk_region
    WHERE
        event_week >= '2020-01-01'
    GROUP BY 1, 2, 3
),
--------------------------------------------
-- Amount of RF and LPV events per house --
--------------------------------------------
house_conversions AS (
    SELECT
        COALESCE(lpv.event_week, rent_flows.week_start ) AS week,
        COALESCE(lpv.macro_id, rent_flows.macro_id ) AS macro_id,
        COALESCE(lpv.id_house,LEFT(rent_flows.sk_house_listing,9) ) AS sk_house,
        status_short,
        SUM(rent_flows.rent_flows) AS rent_flows,
        SUM(lpv.lpv_events) AS lpv_events
    FROM
        lpv
    FULL OUTER JOIN
        rent_flows
         ON rent_flows.week_start = lpv.event_week
         AND rent_flows.macro_id = lpv.macro_id
         AND LEFT(rent_flows.sk_house_listing,9) = lpv.id_house
    GROUP BY 1,2,3,4
),
---------------------------------------------------
-- 3 weeks amount of RF and LPV events per house --
---------------------------------------------------
rolling_avg AS (
    SELECT
        week,
        macro_id,
        sk_house,
        status_short,
        rent_flows,
        lpv_events,
        SUM(rent_flows) OVER (PARTITION BY sk_house ORDER BY sk_house, week  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rent_flows_3w ,
        SUM(lpv_events) OVER (PARTITION BY sk_house ORDER BY sk_house, week  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS lpv_3w,
        rent_flows_3w*1.0/lpv_3w AS lpv_to_rf
    FROM
        house_conversions
),
-----------------------------------------------------------------------------
-- Percentiles of 3 weeks conversion of LPV to RF and LPV per macro region --
-----------------------------------------------------------------------------
avg_region_values_conversion AS (
    SELECT
        week,
        macro_id,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY lpv_to_rf asc) AS percentile_25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY lpv_to_rf asc) AS percentile_50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lpv_to_rf asc) AS percentile_75
    FROM
        rolling_avg
    WHERE
        status_short = 'Ongoing Listing' -- Getting only ongoing listings because they're the houses that were supposed to have RFs and LPV events
    GROUP BY 1, 2
),
------------------------------------------------
-- Percentiles of 3 weeks RF per macro region --
------------------------------------------------
avg_region_values_rent_flows AS (
    SELECT
        week,
        macro_id,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY rent_flows_3w asc) AS percentile_25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY rent_flows_3w asc) AS percentile_50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY rent_flows_3w asc) AS percentile_75
    FROM
        rolling_avg
    WHERE
        status_short = 'Ongoing Listing' -- Getting only ongoing listings because they're the houses that were supposed to have RFs
    GROUP BY 1, 2
),
-------------------------------------------------
-- Percentiles of 3 weeks LPV per macro region --
-------------------------------------------------
avg_region_values_lpv AS (
    SELECT
        week,
        macro_id,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY lpv_3w asc) AS percentile_25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY lpv_3w asc) AS percentile_50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lpv_3w asc) AS percentile_75
    FROM
        rolling_avg
    WHERE
        status_short = 'Ongoing Listing' -- Getting only ongoing listings because they're the houses that were supposed to have LPV event
    GROUP BY 1, 2
)
SELECT
    hc.week,
    hc.macro_id,
    hc.sk_house,
    hc.status_short,
    hc.rent_flows AS house_rent_flows,
    hc.lpv_events AS house_listing_page_view_events,
    hc.rent_flows_3w AS house_rent_flows_3_weeks,
    hc.lpv_3w AS house_listing_page_view_events_3_weeks,
    hc.lpv_to_rf AS house_listing_page_view_to_rent_flow_3_weeks,
    rv.percentile_25 AS region_listing_page_view_to_rent_flow_p25,
    rv.percentile_50 AS region_listing_page_view_to_rent_flow_p50,
    rv.percentile_75 AS region_listing_page_view_to_rent_flow_p75,
    rf.percentile_25 AS region_rent_flow_p25,
    rf.percentile_50 AS region_rent_flow_p50,
    rf.percentile_75 AS region_rent_flow_p75,
    rl.percentile_25 AS region_listing_page_view_p25,
    rl.percentile_50 AS region_listing_page_view_p50,
    rl.percentile_75 AS region_listing_page_view_p75,
    CASE
       WHEN lpv_to_rf between rv.percentile_25 AND rv.percentile_75 THEN 'Normal'
       WHEN lpv_to_rf < rv.percentile_25  THEN 'Cold'
       WHEN lpv_to_rf > rv.percentile_75 THEN 'Hot'
    END AS type_listing_page_view_to_rent_flow,
    CASE
       WHEN rent_flows_3w between rf.percentile_25 AND rf.percentile_75 THEN 'Normal'
       WHEN rent_flows_3w < rf.percentile_25  THEN 'Cold'
       WHEN rent_flows_3w > rf.percentile_75 THEN 'Hot'
    END AS type_rent_flow,
    CASE
       WHEN lpv_3w between rl.percentile_25 AND rl.percentile_75 THEN 'Normal'
       WHEN lpv_3w < rl.percentile_25  THEN 'Cold'
       WHEN lpv_3w > rl.percentile_75 THEN 'Hot'
    END AS type_listing_page_view
FROM
    rolling_avg hc
LEFT JOIN
    avg_region_values_conversion rv
     ON rv.macro_id = hc.macro_id
     AND rv.week = hc.week
LEFT JOIN
    avg_region_values_rent_flows rf
     ON rf.macro_id = hc.macro_id
     AND rf.week = hc.week
LEFT JOIN
    avg_region_values_lpv rl
     ON rl.macro_id = hc.macro_id
     AND rl.week = hc.week