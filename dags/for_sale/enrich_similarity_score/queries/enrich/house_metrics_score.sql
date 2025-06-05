WITH get_metrics_base AS (
    SELECT
        MD5(CONCAT(hldi_1.id_house, 'RENT', hldi_1.year, hldi_1.month, hldi_1.day)) AS id,
        hldi_1.id_house,
        SUM(COALESCE(hldi_2.listing_page_views, 0)) AS base_lpv,
        SUM(COALESCE(hldi_2.search_results_page_views, 0)) AS base_srpv,
        SUM(COALESCE(hldi_2.favorites, 0)) AS base_favorites,
        SUM(COALESCE(hldi_2.visits_booked, 0)) AS base_vb,
        SUM(COALESCE(hldi_2.offers_sent, 0)) AS base_os,
        'RENT' AS business_context,
        DATE_SUB(MAKE_DATE(hldi_1.year, hldi_1.month, hldi_1.day), CAST(IF(hldi_1.days_published < 15, hldi_1.days_published, 15) AS INT) - 1) AS dt_agg_started,
        MAKE_DATE(hldi_1.year, hldi_1.month, hldi_1.day) AS dt_agg_ended,
        hldi_1.year,
        hldi_1.month,
        hldi_1.day
    FROM
        datalake_rental_historical_follow_up.house_listings_daily_info AS hldi_1
    INNER JOIN
        datalake_rental_historical_follow_up.house_listings_daily_info AS hldi_2
            ON hldi_1.id_house = hldi_2.id_house
            AND MAKE_DATE(hldi_2.year, hldi_2.month, hldi_2.day) BETWEEN
                DATE_SUB(MAKE_DATE(hldi_1.year, hldi_1.month, hldi_1.day), CAST(IF(hldi_1.days_published < 15, hldi_1.days_published, 15) AS INT) - 1 )
                AND MAKE_DATE(hldi_1.year, hldi_1.month, hldi_1.day)
    WHERE
        MAKE_DATE(hldi_1.year, hldi_1.month, hldi_1.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND hldi_1.status_history = 'PUBLISHED'
    GROUP BY
        ALL
),
explode_similar AS (
    SELECT
        sh.id,
        sh.id_house,
        EXPLODE(sh.ids_similar) AS id_similar,
        sh.business_context,
        b.dt_agg_started,
        b.dt_agg_ended,
        sh.year,
        sh.month,
        sh.day
    FROM
        datalake_similarity_score.similar_houses AS sh
    LEFT JOIN
        get_metrics_base AS b
            ON b.id_house = sh.id_house
            AND b.business_context = sh.business_context
            AND b.year = sh.year
            AND b.month = sh.month
            AND b.day = sh.day
    WHERE
        MAKE_DATE(sh.year, sh.month, sh.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
get_metrics_similar_1 AS (
    SELECT
        es.id,
        es.id_house,
        es.id_similar,
        SUM(COALESCE(di.listing_page_views, 0)) AS sum_similar_lpv,
        SUM(COALESCE(di.search_results_page_views, 0)) AS sum_similar_srpv,
        SUM(COALESCE(di.favorites, 0)) AS sum_similar_favorites,
        SUM(COALESCE(di.visits_booked, 0)) AS sum_similar_vb,
        SUM(COALESCE(di.offers_sent, 0)) AS sum_similar_os,
        es.business_context,
        es.dt_agg_started,
        es.dt_agg_ended,
        es.year,
        es.month,
        es.day
    FROM
        explode_similar AS es
    LEFT JOIN
        datalake_rental_historical_follow_up.house_listings_daily_info AS di
            ON di.id_house = es.id_similar
            AND di.dt_day BETWEEN es.dt_agg_started AND es.dt_agg_ended
    GROUP BY
        ALL
),
get_metrics_similar_2 AS (
    SELECT
        id,
        id_house,
        COLLECT_LIST(id_similar) AS ids_similar,
        PERCENTILE(sum_similar_lpv, 0.5) AS similar_lpv,
        PERCENTILE(sum_similar_srpv, 0.5) AS similar_srpv,
        PERCENTILE(sum_similar_favorites, 0.5) AS similar_favorites,
        PERCENTILE(sum_similar_vb, 0.5) AS similar_vb,
        PERCENTILE(sum_similar_os, 0.5) AS similar_os,
        business_context,
        dt_agg_started,
        dt_agg_ended,
        year,
        month,
        day
    FROM
        get_metrics_similar_1
    GROUP BY
        ALL
)
SELECT
    COALESCE(s.id, b.id) AS id,
    b.id_house,
    s.ids_similar,
    b.base_lpv,
    b.base_srpv,
    b.base_favorites,
    b.base_vb,
    b.base_os,
    s.similar_lpv,
    s.similar_srpv,
    s.similar_favorites,
    s.similar_vb,
    s.similar_os,
    ROUND((base_lpv + 1) / (similar_lpv + 1), 1) AS calculation_score_lpv,
    ROUND((base_srpv + 1) / (similar_srpv + 1), 1) AS calculation_score_srpv,
    ROUND((base_favorites + 1) / (similar_favorites + 1), 1) AS calculation_score_favorites,
    ROUND((base_vb + 1) / (similar_vb + 1), 1) AS calculation_score_vb,
    ROUND((base_os + 1) / (similar_os + 1), 1) AS calculation_score_os,
    IF(
        s.ids_similar IS NOT NULL,
        CASE
            WHEN calculation_score_lpv >= 1.5 THEN 5
            WHEN calculation_score_lpv >= 1.1 THEN 4
            WHEN calculation_score_lpv <= 0.5 THEN 1
            WHEN calculation_score_lpv <= 0.9 THEN 2
            ELSE 3
        END,
        NULL
    ) AS score_lpv,
    IF(
        s.ids_similar IS NOT NULL,
        CASE
            WHEN calculation_score_srpv >= 1.5 THEN 5
            WHEN calculation_score_srpv >= 1.1 THEN 4
            WHEN calculation_score_srpv <= 0.5 THEN 1
            WHEN calculation_score_srpv <= 0.9 THEN 2
            ELSE 3
        END,
        NULL
    ) AS score_srpv,
    IF(
        s.ids_similar IS NOT NULL,
        CASE
            WHEN calculation_score_favorites >= 1.5 THEN 5
            WHEN calculation_score_favorites >= 1.1 THEN 4
            WHEN calculation_score_favorites <= 0.5 THEN 1
            WHEN calculation_score_favorites <= 0.9 THEN 2
            ELSE 3
        END,
        NULL
    ) AS score_favorites,
    IF(
        s.ids_similar IS NOT NULL,
        CASE
            WHEN calculation_score_vb >= 1.5 THEN 5
            WHEN calculation_score_vb >= 1.1 THEN 4
            WHEN calculation_score_vb <= 0.5 THEN 1
            WHEN calculation_score_vb <= 0.9 THEN 2
            ELSE 3
        END,
        NULL
    ) AS score_vb,
    IF(
        s.ids_similar IS NOT NULL,
        CASE
            WHEN calculation_score_os >= 1.5 THEN 5
            WHEN calculation_score_os >= 1.1 THEN 4
            WHEN calculation_score_os <= 0.5 THEN 1
            WHEN calculation_score_os <= 0.9 THEN 2
            ELSE 3
        END,
        NULL
    ) AS score_os,
    ROUND((score_srpv * 2 + score_lpv * 3 + score_vb * 1 + score_os * 1) / 7) AS final_score,
    b.business_context,
    IF(s.ids_similar IS NOT NULL, "Percentile at percentage 0.5", NULL) AS similar_metric_rule,
    IF(s.ids_similar IS NOT NULL, '(base_metric + 1)/(similar_metric + 1)', NULL) AS score_calculation_rule,
    IF(s.ids_similar IS NOT NULL, '5 IF calculation_score_* >= 1.5; 4 IF calculation_score_* >= 1.1; 1 IF calculation_score_* <= 0.5; 2 IF calculation_score_* <= 0.9; ELSE 3', NULL) AS score_metric_rule,
    IF(s.ids_similar IS NOT NULL, '(score_srpv*2 + score_lpv*3 + score_vb*1 + score_os*1) / 7 rounded', NULL) AS final_score_rule,
    b.dt_agg_started,
    b.dt_agg_ended,
    b.year,
    b.month,
    b.day
FROM
    get_metrics_base AS b
LEFT JOIN
    get_metrics_similar_2 AS s
        ON b.id_house = s.id_house
        AND b.business_context = s.business_context
        AND b.dt_agg_started = s.dt_agg_started
        AND b.dt_agg_ended = s.dt_agg_ended
        AND b.year = s.year
        AND b.month = s.month
        AND b.day = s.day
