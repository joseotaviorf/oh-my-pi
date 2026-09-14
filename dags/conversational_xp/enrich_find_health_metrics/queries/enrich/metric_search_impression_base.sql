/* One row per search listing impression, with the listing price in effect on the search
   day. Base table for Find search health Superset charts and the downstream weekly
   metric tables. */
WITH search_impressions AS (
    SELECT
        GET_JSON_OBJECT(ids, '$.id_search') AS id_search,
        CAST(GET_JSON_OBJECT(ids, '$.id_house') AS INT) AS id_house,
        CAST(GET_JSON_OBJECT(ids, '$.id_user') AS BIGINT) AS id_user,
        UPPER(GET_JSON_OBJECT(dimensions, '$.business_context')) AS business_context,
        GET_JSON_OBJECT(dimensions, '$.city') AS house_city,
        GET_JSON_OBJECT(dimensions, '$.platform') AS platform,
        CAST(GET_JSON_OBJECT(dimensions, '$.absolute_position') AS INT) AS absolute_position,
        TRY_CAST(GET_JSON_OBJECT(dimensions, '$.listing_age') AS INT) AS listing_age,
        GET_JSON_OBJECT(dimensions, '$.rank_model') AS rank_model,
        CAST(GET_JSON_OBJECT(metrics, '$.click') AS INT) AS is_listing_clicked,
        CAST(GET_JSON_OBJECT(metrics, '$.visit_booked') AS INT) AS is_visit_booked,
        CAST(GET_JSON_OBJECT(metrics, '$.offer') AS INT) AS is_offer,
        CAST(GET_JSON_OBJECT(metrics, '$.contract_signed') AS INT) AS is_contract_signed,
        DATE(ts_event) AS dt_search_event,
        ts_event AS ts_search_event,
        year,
        month,
        day
    FROM
        datalake_search.search_impressions
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
        AND GET_JSON_OBJECT(dimensions, '$.business_context') IS NOT NULL
),

price_intervals AS (
    SELECT
        id_house,
        UPPER(business_context) AS business_context,
        price,
        DATE(ts_price_started) AS dt_price_started,
        COALESCE(DATE(ts_price_ended), DATE('2100-01-01')) AS dt_price_ended
    FROM
        datalake_ebdb_pricing.listing_price_change
    WHERE
        is_last_price_of_day = TRUE
        AND DATE(ts_price_started) <= DATE('{end_date}')
        AND COALESCE(DATE(ts_price_ended), DATE('2100-01-01'))
            > DATE_SUB(DATE('{start_date}'), {days_past_30})
)

SELECT
    si.id_search,
    si.id_house,
    si.id_user,
    si.business_context,
    si.house_city,
    si.platform,
    si.absolute_position,
    si.rank_model,
    CASE
        WHEN si.rank_model = 'LTR' AND si.platform = 'app' THEN 'app map'
        WHEN si.rank_model = 'LTR' AND si.platform = 'web' THEN 'SSR web'
        WHEN si.rank_model = 'LTR' THEN 'error'
        ELSE si.rank_model
    END AS rank_model_variant,
    si.listing_age,
    CASE
        WHEN si.listing_age IS NULL THEN 'unknown'
        WHEN si.listing_age <= 7 THEN '1. 0-7d'
        WHEN si.listing_age <= 30 THEN '2. 8-30d'
        WHEN si.listing_age <= 90 THEN '3. 31-90d'
        WHEN si.listing_age <= 180 THEN '4. 91-180d'
        ELSE '5. >180d'
    END AS listing_age_bucket,
    CAST(pi.price AS DOUBLE) AS listing_price_at_search,
    CASE
        WHEN pi.price IS NULL THEN 'unknown'
        WHEN si.business_context = 'RENT' THEN
            CASE
                WHEN pi.price < 1500 THEN '1. < R$1.5k'
                WHEN pi.price < 2000 THEN '2. R$1.5k-2k'
                WHEN pi.price < 3000 THEN '3. R$2k-3k'
                WHEN pi.price < 4000 THEN '4. R$3k-4k'
                WHEN pi.price < 6000 THEN '5. R$4k-6k'
                WHEN pi.price < 10000 THEN '6. R$6k-10k'
                WHEN pi.price < 15000 THEN '7. R$10k-15k'
                ELSE '8. >= R$15k'
            END
        WHEN si.business_context = 'SALE' THEN
            CASE
                WHEN pi.price < 250000 THEN '1. < R$250k'
                WHEN pi.price < 350000 THEN '2. R$250-350k'
                WHEN pi.price < 450000 THEN '3. R$350-450k'
                WHEN pi.price < 600000 THEN '4. R$450-600k'
                WHEN pi.price < 800000 THEN '5. R$600-800k'
                WHEN pi.price < 1200000 THEN '6. R$800k-1.2M'
                WHEN pi.price < 2000000 THEN '7. R$1.2M-2M'
                ELSE '8. >= R$2M'
            END
        ELSE 'unknown'
    END AS listing_price_bucket,
    si.is_listing_clicked,
    si.is_visit_booked,
    si.is_offer,
    si.is_contract_signed,
    si.dt_search_event,
    si.ts_search_event,
    si.year,
    si.month,
    si.day
FROM
    search_impressions AS si
LEFT JOIN
    price_intervals AS pi
        ON pi.id_house = si.id_house
        AND pi.business_context = si.business_context
        AND si.dt_search_event >= pi.dt_price_started
        AND si.dt_search_event < pi.dt_price_ended
