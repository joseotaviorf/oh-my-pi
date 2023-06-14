
WITH dates AS (
    SELECT DISTINCT
        dt_rec_received as dt,
        business_context AS business_context
    FROM
        datalake_recommendations.recommendation
    WHERE
        recommendation.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
),

_catalog AS (
    SELECT
        dt,
        business_context,
        COUNT(DISTINCT id_item) as distinct_catalog_items_per_day
    FROM (
        SELECT
            dates.dt,
            dates.business_context,
            recommendation_catalog.id_item AS id_item
        FROM
            dates
        LEFT JOIN
            datalake_recommendations.recommendation_catalog AS recommendation_catalog
        ON
            DATE(recommendation_catalog.ts_status_started) <= dates.dt
            AND (
                DATE(recommendation_catalog.ts_status_ended) >= dates.dt
                OR recommendation_catalog.ts_status_ended IS NULL
            )
            AND dates.business_context = recommendation_catalog.business_context

        UNION ALL

        SELECT
            dt_rec_received as dt,
            business_context,
            id_item
        FROM
            datalake_recommendations.recommendation AS recommendation
    )
    GROUP BY dt, business_context
),

distinct_users_per_item_day AS (
    SELECT
        DATE(ts_interaction) as dt,
        business_context,
        id_item,
        COUNT(DISTINCT id_user) as distinct_users_per_day
    FROM
        datalake_recommendations.item_interaction
    WHERE MAKE_DATE(item_interaction.year, item_interaction.month, item_interaction.day)
            BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
    GROUP BY
        DATE(ts_interaction), business_context, id_item
),

item_popularity_rank_per_day AS (
    SELECT
        dt,
        business_context,
        id_item,
        RANK() OVER(
            PARTITION BY dt, business_context
            ORDER BY distinct_users_per_day DESC
        ) - 1 AS popularity
    FROM distinct_users_per_item_day
),

item_popularity_rank_per_day_normalize AS (
    SELECT
        item_popularity_rank_per_day.dt,
        item_popularity_rank_per_day.business_context,
        item_popularity_rank_per_day.id_item,
        COALESCE(1 - (popularity / COALESCE(GREATEST(_catalog.distinct_catalog_items_per_day,popularity),0)),0)  AS popularity
    FROM item_popularity_rank_per_day
    LEFT JOIN _catalog
        ON _catalog.dt = item_popularity_rank_per_day.dt
        AND _catalog.business_context = item_popularity_rank_per_day.business_context
)

SELECT
    id_rec,
    COALESCE(popularity, 0) AS popularity,
    dt_rec_received
FROM
    datalake_recommendations.recommendation AS recommendation
LEFT JOIN
    item_popularity_rank_per_day_normalize
    ON item_popularity_rank_per_day_normalize.dt = dt_rec_received
    AND item_popularity_rank_per_day_normalize.business_context = recommendation.business_context
    AND item_popularity_rank_per_day_normalize.id_item = recommendation.id_item
WHERE
    recommendation.dt_rec_received BETWEEN DATE_SUB(DATE('{start_date}'), {days_past}) AND DATE('{end_date}')
