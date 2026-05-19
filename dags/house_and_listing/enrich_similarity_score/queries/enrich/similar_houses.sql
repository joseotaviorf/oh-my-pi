WITH get_sale_visits AS (
    SELECT
        oldi_1.id_house,
        SUM(oldi_2.qt_visits_booked) AS qt_visits_booked_last_30d,
        oldi_1.year,
        oldi_1.month,
        oldi_1.day
    FROM
        datalake_sale_ongoing_listings.ongoing_listings_daily_info AS oldi_1
    INNER JOIN
        datalake_sale_ongoing_listings.ongoing_listings_daily_info AS oldi_2
            ON oldi_1.id_house = oldi_2.id_house
            AND MAKE_DATE(oldi_2.year, oldi_2.month, oldi_2.day) BETWEEN
                DATE_SUB(MAKE_DATE(oldi_1.year, oldi_1.month, oldi_1.day), 30)
                AND MAKE_DATE(oldi_1.year, oldi_1.month, oldi_1.day)
    WHERE
        MAKE_DATE(oldi_1.year, oldi_1.month, oldi_1.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        ALL
),
sale_with_visits AS (
    SELECT
        oldi.id_house,
        oldi.sale_price AS price,
        oldi.calculator_min_price AS p_10,
        oldi.calculator_max_price AS p_90,
        COALESCE(oldi.sale_price <= oldi.calculator_p70_price, FALSE) AS is_below_predicted_price_70,
        COALESCE(v.qt_visits_booked_last_30d > 0, FALSE) AS has_visits_booked_last_30d,
        h.city,
        h.type,
        h.total_area,
        h.lat,
        h.lng,
        30 AS rule_days_published,
        oldi.days_published,
        'SALE' AS business_context,
        oldi.year,
        oldi.month,
        oldi.day
    FROM
        datalake_sale_ongoing_listings.ongoing_listings_daily_info AS oldi
    INNER JOIN
        datalake_ebdb_listing.house AS h
            ON h.id = oldi.id_house
    INNER JOIN
        get_sale_visits AS v
            ON oldi.id_house = v.id_house
            AND oldi.year = v.year
            AND oldi.month = v.month
            AND oldi.day = v.day
    WHERE
        MAKE_DATE(oldi.year, oldi.month, oldi.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND oldi.days_published >= 1
),
get_rent_sale_houses AS (
    SELECT
        hldi.id_house,
        hldi.rent AS price,
        hldi.p_10,
        hldi.p_90,
        COALESCE(hldi.rent <= hldi.p_70, FALSE) AS is_below_predicted_price_70,
        NULL AS has_visits_booked_last_30d,
        h.city,
        h.type,
        h.total_area,
        h.lat,
        h.lng,
        15 AS rule_days_published,
        hldi.days_published,
        'RENT' AS business_context,
        hldi.year,
        hldi.month,
        hldi.day
    FROM
        datalake_rental_historical_follow_up.house_listings_daily_info AS hldi
    INNER JOIN
        datalake_ebdb_listing.house AS h
            ON h.id = hldi.id_house
    WHERE
        MAKE_DATE(hldi.year, hldi.month, hldi.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND hldi.status_history = 'PUBLISHED'
        AND hldi.days_published >= 1

    UNION ALL

    SELECT
        id_house,
        price,
        p_10,
        p_90,
        is_below_predicted_price_70,
        has_visits_booked_last_30d,
        city,
        type,
        total_area,
        lat,
        lng,
        rule_days_published,
        days_published,
        business_context,
        year,
        month,
        day
    FROM
        sale_with_visits
),
get_similar AS (
    SELECT
        base.id_house AS base_id_house,
        similar.id_house AS similar_id_house,
        base.days_published,
        base.business_context,
        default.HAVERSINE_DISTANCE(similar.lng, similar.lat, base.lng, base.lat) AS distance,
        (
            similar.price BETWEEN base.p_10 AND base.p_90
            AND similar.total_area BETWEEN base.total_area * 0.7 AND base.total_area * 1.3
        ) AS has_price_and_area_match,
        base.year,
        base.month,
        base.day
    FROM
        get_rent_sale_houses AS base
    LEFT JOIN
        get_rent_sale_houses AS similar
            ON base.year = similar.year
            AND base.month = similar.month
            AND base.day = similar.day
            AND base.id_house != similar.id_house
            AND base.business_context = similar.business_context
            AND base.city = similar.city
            AND base.type = similar.type
            AND COALESCE(similar.has_visits_booked_last_30d, TRUE)
            AND similar.is_below_predicted_price_70
            AND similar.days_published >= IF(base.days_published < base.rule_days_published, base.days_published, base.rule_days_published)
),
get_similar_rules AS (
    SELECT
        base_id_house,
        COLLECT_LIST(similar_id_house) AS ids_similar,
        1 AS rule_id,
        days_published,
        business_context,
        year,
        month,
        day
    FROM
        get_similar
    WHERE
        has_price_and_area_match
        AND distance <= 2
    GROUP BY
        ALL
    HAVING
        SIZE(ids_similar) >= 3

    UNION ALL

    SELECT
        base_id_house,
        COLLECT_LIST(similar_id_house) AS ids_similar,
        2 AS rule_id,
        days_published,
        business_context,
        year,
        month,
        day
    FROM
        get_similar
    WHERE
        has_price_and_area_match
        AND distance <= 5
    GROUP BY
        ALL
    HAVING
        SIZE(ids_similar) >= 3

    UNION ALL

    SELECT
        base_id_house,
        COLLECT_LIST(similar_id_house) AS ids_similar,
        3 AS rule_id,
        days_published,
        business_context,
        year,
        month,
        day
    FROM
        get_similar
    GROUP BY
        ALL
    HAVING
        SIZE(ids_similar) >= 3
),
-- Choose the best rule (smallest rule_id) for each base house
get_best_rule AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY base_id_house, business_context, year, month, day ORDER BY rule_id ASC) AS rn
    FROM
        get_similar_rules
)
SELECT
    MD5(CONCAT(base_id_house, business_context, year, month, day)) AS id,
    base_id_house AS id_house,
    ids_similar,
    CASE
        WHEN rule_id = 1 THEN
            IF(
                business_context = 'RENT',
                "1. status = PUBLISHED; if base publication time < 15 then similar publication time >= base publication time, else similar publication time >= 15; similar price <= p_70; similar_price between base p_10 and base p_90; similar_area between base_area * 0.7 and base_area * 1.3; similar city, type and business context are the same as the base; similar is not the base; haversine_distance <= 2; at least 3 similar",
                "1. status = PUBLISHED; if base publication time < 30 then similar publication time >= base publication time, else similar publication time >= 30; similar price <= p_70; similar_price between base p_10 and base p_90; similar_area between base_area * 0.7 and base_area * 1.3; similar has at least 1 visit booked in the last 30 days; similar city, type and business context are the same as the base; similar is not the base; haversine_distance <= 2; at least 3 similar"
            )
        WHEN rule_id = 2 THEN
            IF(
                business_context = 'RENT',
                "2. status = PUBLISHED; if base publication time < 15 then similar publication time >= base publication time, else similar publication time >= 15; similar price <= p_70; similar_price between base p_10 and base p_90; similar_area between base_area * 0.7 and base_area * 1.3; similar city, type and business context are the same as the base; similar is not the base; haversine_distance <= 5; at least 3 similar",
                "2. status = PUBLISHED; if base publication time < 30 then similar publication time >= base publication time, else similar publication time >= 30; similar price <= p_70; similar_price between base p_10 and base p_90; similar_area between base_area * 0.7 and base_area * 1.3; similar has at least 1 visit booked in the last 30 days; similar city, type and business context are the same as the base; similar is not the base; haversine_distance <= 5; at least 3 similar"
            )
        WHEN rule_id = 3 THEN
            IF(
                business_context = 'RENT',
                "3. status = PUBLISHED; if base publication time < 15 then similar publication time >= base publication time, else similar publication time >= 15; similar price <= p_70; similar city, type and business context are the same as the base; similar is not the base; at least 3 similar",
                "3. status = PUBLISHED; if base publication time < 30 then similar publication time >= base publication time, else similar publication time >= 30; similar price <= p_70; similar has at least 1 visit booked in the last 30 days; similar city, type and business context are the same as the base; similar is not the base; at least 3 similar"
            )
    END AS similar_rule,
    SIZE(ids_similar) AS qty_similar,
    days_published,
    business_context,
    year,
    month,
    day
FROM
    get_best_rule
WHERE
    rn = 1
