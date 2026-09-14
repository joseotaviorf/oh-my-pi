WITH user_search_house AS (
    SELECT DISTINCT
        id_user,
        id_search,
        id_house,
        business_context,
        DATE_TRUNC('week', ts_search_event) AS ts_search_event_week
    FROM
        datalake_search.metric_search_impression_base
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
        /* Each run overwrites the week partitions it emits, so keep only weeks fully
           covered by the read window: a partial week must never replace a complete one. */
        AND DATE_TRUNC('week', ts_search_event) BETWEEN
            DATE_TRUNC('week', DATE_ADD(DATE_SUB(DATE('{start_date}'), {days_past_30}), 6))
            AND DATE_SUB(DATE_TRUNC('week', DATE_ADD(DATE('{end_date}'), 1)), 7)
),

qualified_users AS (
    SELECT
        business_context,
        ts_search_event_week,
        id_user,
        COUNT(DISTINCT id_search) AS n_searches
    FROM
        user_search_house
    GROUP BY
        business_context,
        ts_search_event_week,
        id_user
    HAVING
        COUNT(DISTINCT id_search) >= 2
),

house_stats AS (
    SELECT
        ush.business_context,
        ush.ts_search_event_week,
        ush.id_user,
        ush.id_house,
        COUNT(DISTINCT ush.id_search) AS n_searches_containing_house
    FROM
        user_search_house AS ush
    INNER JOIN
        qualified_users AS qu
            ON qu.business_context = ush.business_context
            AND qu.ts_search_event_week = ush.ts_search_event_week
            AND qu.id_user = ush.id_user
    GROUP BY
        ush.business_context,
        ush.ts_search_event_week,
        ush.id_user,
        ush.id_house
),

user_stats AS (
    SELECT
        hs.business_context,
        hs.ts_search_event_week,
        hs.id_user,
        qu.n_searches,
        COUNT(*) AS n_unique_houses,
        SUM(hs.n_searches_containing_house) AS n_total_pairs,
        SUM(hs.n_searches_containing_house) - COUNT(*) AS n_repeated_appearances,
        COUNT_IF(hs.n_searches_containing_house >= 2) AS n_houses_seen_more_than_once
    FROM
        house_stats AS hs
    INNER JOIN
        qualified_users AS qu
            ON qu.business_context = hs.business_context
            AND qu.ts_search_event_week = hs.ts_search_event_week
            AND qu.id_user = hs.id_user
    GROUP BY
        hs.business_context,
        hs.ts_search_event_week,
        hs.id_user,
        qu.n_searches
)

SELECT
    ts_search_event_week,
    business_context,
    COUNT(*) AS n_users_multi_search,
    AVG(CAST(n_searches AS DOUBLE)) AS avg_searches_per_multi_search_user,
    AVG(CAST(n_unique_houses AS DOUBLE)) AS avg_unique_houses_seen,
    PERCENTILE_APPROX(n_searches, 0.50) AS median_searches_per_multi_search_user,
    PERCENTILE_APPROX(n_unique_houses, 0.50) AS median_unique_houses_seen,
    AVG(CAST(n_repeated_appearances AS DOUBLE) / NULLIF(n_total_pairs, 0)) AS impression_repetition_rate,
    AVG(CAST(n_houses_seen_more_than_once AS DOUBLE) / NULLIF(n_unique_houses, 0)) AS houses_repetition_rate,
    CAST(COUNT_IF(n_repeated_appearances > 0) AS DOUBLE) / COUNT(*) AS pct_users_with_any_repetition,
    YEAR(ts_search_event_week) AS year,
    MONTH(ts_search_event_week) AS month,
    DAY(ts_search_event_week) AS day
FROM
    user_stats
GROUP BY
    ts_search_event_week,
    business_context
