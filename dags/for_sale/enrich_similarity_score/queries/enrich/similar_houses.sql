WITH get_rent_houses AS (
    SELECT
        hldi.id_house,
        hldi.status_history AS status,
        hldi.rent AS price,
        hldi.p_10,
        hldi.p_90,
        IF(hldi.rent <= hldi.p_70, TRUE, FALSE) AS is_below_predicted_price_70,
        h.city,
        h.type,
        h.total_area,
        h.lat,
        h.lng,
        DATEDIFF(DAY, DATE(sh.ts_last_publication), hldi.dt_day) + 1 AS days_published,
        sh.business_context,
        sh.ts_last_publication,
        hldi.year,
        hldi.month,
        hldi.day
    FROM
        datalake_rental_historical_follow_up.house_listings_daily_info AS hldi
    INNER JOIN
        datalake_ebdb_listing.listing_business_context_status_history AS sh
            ON sh.id_house = hldi.id_house
            AND sh.business_context = 'RENT'
            AND hldi.dt_day >= DATE(sh.ts_state_started)
            AND hldi.dt_day < COALESCE(DATE(sh.ts_state_ended), CURRENT_DATE)
    INNER JOIN
        datalake_ebdb_listing.house AS h
            ON h.id = hldi.id_house
    WHERE
        MAKE_DATE(hldi.year, hldi.month, hldi.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND hldi.status_history = 'PUBLISHED'
),
get_rent_similar AS (
    SELECT
        base.id_house AS base_id_house,
        similar.id_house AS similar_id_house,
        base.lat AS base_lat,
        base.lng AS base_lng,
        similar.lat AS similar_lat,
        similar.lng AS similar_lng,
        default.HAVERSINE_DISTANCE(similar.lng, similar.lat, base.lng, base.lat) AS distance,
        base.days_published,
        base.business_context,
        base.year,
        base.month,
        base.day
    FROM
        get_rent_houses AS base
    LEFT JOIN
        get_rent_houses AS similar
            ON similar.id_house != base.id_house
            AND similar.business_context = base.business_context
            AND similar.is_below_predicted_price_70
            AND similar.price BETWEEN base.p_10 AND base.p_90
            AND similar.total_area BETWEEN base.total_area * 0.7 AND base.total_area * 1.3
            AND similar.city = base.city
            AND similar.type = base.type
            AND similar.days_published >= IF(base.days_published < 15, base.days_published, 15)
            AND similar.year = base.year
            AND similar.month = base.month
            AND similar.day = base.day
),
get_frst_distance AS (
    SELECT
        MD5(CONCAT(base_id_house, business_context, year, month, day)) AS id,
        base_id_house AS id_house,
        COLLECT_LIST(similar_id_house) AS ids_similar,
        "1. status = PUBLISHED; if base publication time < 15 then similar publication time >= base publication time, else similar publication time >= 15; similar price <= p_70; similar_price between base p_10 and base p_90; similar_area between base_area * 0.7 and base_area * 1.3; similar city, type and business context are the same as the base; similar is not the base; haversine_distance <= 2; at least 3 similar" AS similar_rule,
        days_published,
        business_context,
        year,
        month,
        day
    FROM
        get_rent_similar
    WHERE
        distance <= 2
    GROUP BY
        ALL
    HAVING
        SIZE(ids_similar) >= 3
),
get_scnd_distance AS (
    SELECT
        MD5(CONCAT(s.base_id_house, s.business_context, s.year, s.month, s.day)) AS id,
        s.base_id_house AS id_house,
        COLLECT_LIST(s.similar_id_house) AS ids_similar,
        "2. status = PUBLISHED; if base publication time < 15 then similar publication time >= base publication time, else similar publication time >= 15; similar price <= p_70; similar_price between base p_10 and base p_90; similar_area between base_area * 0.7 and base_area * 1.3; similar city, type and business context are the same as the base; similar is not the base; haversine_distance <= 5; at least 3 similar" AS similar_rule,
        s.days_published,
        s.business_context,
        s.year,
        s.month,
        s.day
    FROM
        get_rent_similar AS s
    LEFT JOIN
        get_frst_distance AS d1
            ON d1.id_house = s.base_id_house
            AND d1.year = s.year
            AND d1.month = s.month
            AND d1.day = s.day
    WHERE
        d1.id_house IS NULL
        AND s.distance <= 5
    GROUP BY
        ALL
    HAVING
        SIZE(ids_similar) >= 3
),
get_rent_similar_fallback AS (
    SELECT
        base.id_house AS base_id_house,
        similar.id_house AS similar_id_house,
        base.days_published,
        base.business_context,
        base.year,
        base.month,
        base.day
    FROM
        get_rent_houses AS base
    LEFT JOIN
        get_rent_houses AS similar
            ON similar.id_house != base.id_house
            AND similar.business_context = base.business_context
            AND similar.is_below_predicted_price_70
            AND similar.city = base.city
            AND similar.type = base.type
            AND similar.days_published >= IF(base.days_published < 15, base.days_published, 15)
            AND similar.year = base.year
            AND similar.month = base.month
            AND similar.day = base.day
    LEFT JOIN
        get_frst_distance AS d1
            ON d1.id_house = base.id_house
            AND d1.year = base.year
            AND d1.month = base.month
            AND d1.day = base.day
    LEFT JOIN
        get_scnd_distance AS d2
            ON d2.id_house = base.id_house
            AND d2.year = base.year
            AND d2.month = base.month
            AND d2.day = base.day
    WHERE
        d1.id_house IS NULL
        AND d2.id_house IS NULL
),
get_filtered_similar_fallback AS (
    SELECT
        MD5(CONCAT(base_id_house, business_context, year, month, day)) AS id,
        base_id_house AS id_house,
        COLLECT_LIST(similar_id_house) AS ids_similar,
        "3. status = PUBLISHED; if base publication time < 15 then similar publication time >= base publication time, else similar publication time >= 15; similar price <= p_70; similar city, type and business context are the same as the base; similar is not the base; at least 3 similar" AS similar_rule,
        days_published,
        business_context,
        year,
        month,
        day
    FROM
        get_rent_similar_fallback
    GROUP BY
        ALL
    HAVING
        SIZE(ids_similar) >= 3
)
SELECT
    id,
    id_house,
    ids_similar,
    similar_rule,
    SIZE(ids_similar) AS qty_similar,
    days_published,
    business_context,
    year,
    month,
    day
FROM
    get_frst_distance
UNION ALL
SELECT
    id,
    id_house,
    ids_similar,
    similar_rule,
    SIZE(ids_similar) AS qty_similar,
    days_published,
    business_context,
    year,
    month,
    day
FROM
    get_scnd_distance
UNION ALL
SELECT
    id,
    id_house,
    ids_similar,
    similar_rule,
    SIZE(ids_similar) AS qty_similar,
    days_published,
    business_context,
    year,
    month,
    day
FROM
    get_filtered_similar_fallback
