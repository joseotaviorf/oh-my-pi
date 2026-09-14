WITH search_impressions AS (
    SELECT
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

house_impressions AS (
    SELECT
        ts_search_event_week,
        business_context,
        id_house,
        COUNT(*) AS n_impressions
    FROM
        search_impressions
    GROUP BY
        ts_search_event_week,
        business_context,
        id_house
),

ranked_impressions AS (
    SELECT
        ts_search_event_week,
        business_context,
        id_house,
        n_impressions,
        PERCENT_RANK() OVER (
            PARTITION BY ts_search_event_week, business_context
            ORDER BY n_impressions DESC
        ) AS pct_rank,
        SUM(n_impressions) OVER (
            PARTITION BY ts_search_event_week, business_context
        ) AS n_impressions_week
    FROM
        house_impressions
),

banded_impressions AS (
    SELECT
        ts_search_event_week,
        business_context,
        id_house,
        n_impressions,
        n_impressions_week,
        CASE
            WHEN pct_rank <= 0.01 THEN '1. Top 1%'
            WHEN pct_rank <= 0.10 THEN '2. Top 1-10%'
            WHEN pct_rank <= 0.50 THEN '3. Top 10-50%'
            ELSE '4. Bottom 50%'
        END AS exposure_band
    FROM
        ranked_impressions
)

SELECT
    ts_search_event_week,
    business_context,
    exposure_band,
    COUNT(*) AS n_houses,
    SUM(n_impressions) AS n_impressions,
    MAX(n_impressions_week) AS n_impressions_week,
    CAST(SUM(n_impressions) AS DOUBLE) / MAX(n_impressions_week) AS share_of_impressions,
    CAST(COUNT(*) AS DOUBLE) / SUM(COUNT(*)) OVER (
        PARTITION BY ts_search_event_week, business_context
    ) AS share_of_houses,
    CAST(SUM(n_impressions) AS DOUBLE) / COUNT(*) AS avg_impressions_per_house,
    PERCENTILE_APPROX(n_impressions, 0.50) AS median_impressions_per_house,
    MAX(n_impressions) AS max_impressions_per_house,
    YEAR(ts_search_event_week) AS year,
    MONTH(ts_search_event_week) AS month,
    DAY(ts_search_event_week) AS day
FROM
    banded_impressions
GROUP BY
    ts_search_event_week,
    business_context,
    exposure_band
