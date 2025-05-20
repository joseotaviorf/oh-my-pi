WITH get_metrics_base AS (
    SELECT
        sh.id,
        sh.id_house,
        SUM(COALESCE(di.listing_page_views, 0)) AS base_lpv,
        SUM(COALESCE(di.search_results_page_views, 0)) AS base_srpv,
        SUM(COALESCE(di.visits_booked, 0)) AS base_vb,
        SUM(COALESCE(di.offers_sent, 0)) AS base_os,
        sh.business_context,
        DATE_SUB(MAKE_DATE(sh.year, sh.month, sh.day), CAST(IF(sh.days_published < 15, sh.days_published, 15) AS INT)) AS dt_agg_started,
        MAKE_DATE(sh.year, sh.month, sh.day) AS dt_agg_ended,
        sh.year,
        sh.month,
        sh.day
    FROM
        datalake_similarity_score.similar_houses AS sh
    LEFT JOIN
        datalake_rental_historical_follow_up.house_listings_daily_info AS di
            ON di.id_house = sh.id_house
            AND di.dt_day > DATE_SUB(MAKE_DATE(sh.year, sh.month, sh.day), CAST(IF(sh.days_published < 15, sh.days_published, 15) AS INT))
            AND di.dt_day <= MAKE_DATE(sh.year, sh.month, sh.day)
    WHERE
        MAKE_DATE(sh.year, sh.month, sh.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        ALL
),
explode_similar AS (
    SELECT
        id_house,
        EXPLODE(ids_similar) AS id_similar,
        business_context,
        DATE_SUB(MAKE_DATE(year, month, day), CAST(IF(days_published < 15, days_published, 15) AS INT)) AS dt_agg_started,
        MAKE_DATE(year, month, day) AS dt_agg_ended,
        year,
        month,
        day
    FROM
        datalake_similarity_score.similar_houses
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
get_metrics_similar_1 AS (
    SELECT
        es.id_house,
        es.id_similar,
        SUM(COALESCE(di.listing_page_views, 0)) AS sum_similar_lpv,
        SUM(COALESCE(di.search_results_page_views, 0)) AS sum_similar_srpv,
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
            AND di.dt_day > es.dt_agg_started
            AND di.dt_day <= es.dt_agg_ended
    GROUP BY
        ALL
),
get_metrics_similar_2 AS (
    SELECT
        id_house,
        COLLECT_LIST(id_similar) AS ids_similar,
        PERCENTILE(sum_similar_lpv, 0.5) AS similar_lpv,
        PERCENTILE(sum_similar_srpv, 0.5) AS similar_srpv,
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
    b.id,
    b.id_house,
    s.ids_similar,
    b.base_lpv,
    b.base_srpv,
    b.base_vb,
    b.base_os,
    s.similar_lpv,
    s.similar_srpv,
    s.similar_vb,
    s.similar_os,
    ROUND((base_lpv + 1) / (similar_lpv + 1), 1) AS calculation_score_lpv,
    ROUND((base_srpv + 1) / (similar_srpv + 1), 1) AS calculation_score_srpv,
    ROUND((base_vb + 1) / (similar_vb + 1), 1) AS calculation_score_vb,
    ROUND((base_os + 1) / (similar_os + 1), 1) AS calculation_score_os,
    CASE
        WHEN calculation_score_lpv >= 1.5 THEN 5
        WHEN calculation_score_lpv >= 1.1 THEN 4
        WHEN calculation_score_lpv <= 0.5 THEN 1
        WHEN calculation_score_lpv <= 0.9 THEN 2
        ELSE 3
    END AS score_lpv,
    CASE
        WHEN calculation_score_srpv >= 1.5 THEN 5
        WHEN calculation_score_srpv >= 1.1 THEN 4
        WHEN calculation_score_srpv <= 0.5 THEN 1
        WHEN calculation_score_srpv <= 0.9 THEN 2
        ELSE 3
    END AS score_srpv,
    CASE
        WHEN calculation_score_vb >= 1.5 THEN 5
        WHEN calculation_score_vb >= 1.1 THEN 4
        WHEN calculation_score_vb <= 0.5 THEN 1
        WHEN calculation_score_vb <= 0.9 THEN 2
        ELSE 3
    END AS score_vb,
    CASE
        WHEN calculation_score_os >= 1.5 THEN 5
        WHEN calculation_score_os >= 1.1 THEN 4
        WHEN calculation_score_os <= 0.5 THEN 1
        WHEN calculation_score_os <= 0.9 THEN 2
        ELSE 3
    END AS score_os,
    ROUND((score_srpv * 2 + score_lpv * 3 + score_vb * 1 + score_os * 1) / 7) AS final_score,
    b.business_context,
    "Percentile at percentage 0.5" AS similar_metric_rule,
    '(base_metric + 1)/(similar_metric + 1)' AS score_calculation_rule,
    '5 IF calculation_score_* >= 1.5; 4 IF calculation_score_* >= 1.1; 1 IF calculation_score_* <= 0.5; 2 IF calculation_score_* <= 0.9; ELSE 3' AS score_metric_rule,
    '(score_srpv*2 + score_lpv*3 + score_vb*1 + score_os*1) / 7 rounded' AS final_score_rule,
    b.dt_agg_started,
    b.dt_agg_ended,
    b.year,
    b.month,
    b.day
FROM
    get_metrics_base AS b
INNER JOIN
    get_metrics_similar_2 AS s
        ON b.id_house = s.id_house
        AND b.business_context = s.business_context
        AND b.dt_agg_started = s.dt_agg_started
        AND b.dt_agg_ended = s.dt_agg_ended
        AND b.year = s.year
        AND b.month = s.month
        AND b.day = s.day
