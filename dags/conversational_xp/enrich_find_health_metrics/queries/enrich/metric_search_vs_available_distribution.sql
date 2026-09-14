/* Every calendar week and month overlapping [{start_date}, {end_date}]. A daily run has
   start_date = end_date and so emits just the current week and month, while a run
   triggered with an older load_start_date backfills every period since then. */
WITH period_bounds AS (
    SELECT
        'week' AS period_type,
        period_start,
        DATE_ADD(period_start, 6) AS period_end
    FROM (
        SELECT EXPLODE(
            SEQUENCE(
                DATE(DATE_TRUNC('week', DATE('{start_date}'))),
                DATE(DATE_TRUNC('week', DATE('{end_date}'))),
                INTERVAL 1 WEEK
            )
        ) AS period_start
    ) AS week_starts

    UNION ALL

    SELECT
        'month' AS period_type,
        period_start,
        LAST_DAY(period_start) AS period_end
    FROM (
        SELECT EXPLODE(
            SEQUENCE(
                DATE(DATE_TRUNC('month', DATE('{start_date}'))),
                DATE(DATE_TRUNC('month', DATE('{end_date}'))),
                INTERVAL 1 MONTH
            )
        ) AS period_start
    ) AS month_starts
),

search_impressions AS (
    SELECT
        business_context,
        listing_price_at_search AS price,
        CAST(listing_age AS DOUBLE) AS age_days,
        dt_search_event
    FROM
        datalake_search.metric_search_impression_base
    WHERE
        /* Reach back to the start of the earliest period being written, not just to
           {start_date}. On a daily run that is the current week's Monday, so the week
           partition is rebuilt from whole-week data rather than from a single day. */
        MAKE_DATE(year, month, day) BETWEEN
            LEAST(
                DATE(DATE_TRUNC('week', DATE('{start_date}'))),
                DATE(DATE_TRUNC('month', DATE('{start_date}')))
            )
            AND DATE('{end_date}')
),

/* Fan each impression out to the calendar week and the calendar month containing it, so
   the join to period_bounds below has a hash key. Joining straight on
   dt_search_event BETWEEN period_start AND period_end has no equi-key and plans as a
   BroadcastNestedLoopJoin on EMR. A search date falls in exactly one week and exactly one
   month, so the truncated date is an exact bucket rather than an approximation. */
impression_periods AS (
    SELECT
        period_type,
        CASE period_type
            WHEN 'week' THEN DATE(DATE_TRUNC('week', si.dt_search_event))
            ELSE DATE(DATE_TRUNC('month', si.dt_search_event))
        END AS period_start,
        si.business_context,
        si.price,
        si.age_days
    FROM
        search_impressions AS si
    LATERAL VIEW EXPLODE(ARRAY('week', 'month')) exploded_periods AS period_type
),

exposed_impressions AS (
    SELECT
        pb.period_type,
        pb.period_start,
        pb.period_end,
        ip.business_context,
        ip.price,
        ip.age_days
    FROM
        impression_periods AS ip
    INNER JOIN
        period_bounds AS pb
            ON pb.period_type = ip.period_type
            AND pb.period_start = ip.period_start
),

available_rent AS (
    SELECT
        'RENT' AS business_context,
        CAST(hl.rent AS DOUBLE) AS price,
        CAST(DATEDIFF(CURRENT_DATE(), hl.ts_publicated) AS DOUBLE) AS age_days
    FROM
        datalake_ebdb_listing.house_listing AS hl
    WHERE
        hl.country_code = 'BR'
        AND hl.is_last_version = TRUE
        AND hl.version <> 0
        AND hl.is_for_rent = TRUE
        AND LOWER(hl.status) IN ('published', 'publicado')
),

available_sale AS (
    SELECT
        'SALE' AS business_context,
        CAST(hse.sale_price AS DOUBLE) AS price,
        CAST(DATEDIFF(CURRENT_DATE(), lbc.ts_last_listing) AS DOUBLE) AS age_days
    FROM
        datalake_ebdb_listing.listing_business_context AS lbc
    INNER JOIN
        datalake_ebdb_listing.house AS hse
            ON hse.id = lbc.id_house
    WHERE
        lbc.country_code = 'BR'
        AND lbc.business_context = 'SALE'
        AND lbc.status = 'PUBLISHED'
),

available_listings AS (
    SELECT
        business_context,
        price,
        age_days
    FROM
        available_rent
    UNION ALL
    SELECT
        business_context,
        price,
        age_days
    FROM
        available_sale
),

agg_exposed AS (
    SELECT
        period_type,
        period_start,
        period_end,
        business_context,
        COUNT(*) AS n_exposed,
        CONCAT(
            PERCENTILE_APPROX(price, ARRAY(0.10, 0.25, 0.50, 0.75, 0.90)),
            ARRAY(AVG(price))
        ) AS price_stats,
        CONCAT(
            PERCENTILE_APPROX(age_days, ARRAY(0.10, 0.25, 0.50, 0.75, 0.90)),
            ARRAY(AVG(age_days))
        ) AS age_stats
    FROM
        exposed_impressions
    GROUP BY
        period_type,
        period_start,
        period_end,
        business_context
),

agg_available AS (
    SELECT
        business_context,
        COUNT(*) AS n_available,
        CONCAT(
            PERCENTILE_APPROX(price, ARRAY(0.10, 0.25, 0.50, 0.75, 0.90)),
            ARRAY(AVG(price))
        ) AS price_stats,
        CONCAT(
            PERCENTILE_APPROX(age_days, ARRAY(0.10, 0.25, 0.50, 0.75, 0.90)),
            ARRAY(AVG(age_days))
        ) AS age_stats
    FROM
        available_listings
    GROUP BY
        business_context
),

/* Spine keeps the partition columns non-null even if a business context is missing
   from one side. The available side covers exactly these two contexts. */
period_contexts AS (
    SELECT
        pb.period_type,
        pb.period_start,
        pb.period_end,
        ctx.business_context
    FROM
        period_bounds AS pb
    CROSS JOIN (
        SELECT business_context
        FROM VALUES ('RENT'), ('SALE') AS contexts(business_context)
    ) AS ctx
),

stats_labels AS (
    SELECT stats, stats_position
    FROM VALUES
        ('p10', 0),
        ('p25', 1),
        ('p50', 2),
        ('p75', 3),
        ('p90', 4),
        ('mean', 5)
        AS stats_labels(stats, stats_position)
),

distribution AS (
    SELECT
        pctx.business_context,
        pctx.period_type,
        stl.stats,
        aex.price_stats[stl.stats_position] AS exposed_price_raw,
        aav.price_stats[stl.stats_position] AS available_listings_price_raw,
        aex.age_stats[stl.stats_position] AS exposed_impressions_age_days_raw,
        aav.age_stats[stl.stats_position] AS available_listings_age_days_raw,
        aex.n_exposed,
        aav.n_available,
        pctx.period_end <= DATE('{end_date}') AS is_period_complete,
        pctx.period_start,
        pctx.period_end,
        LEAST(pctx.period_end, DATE('{end_date}')) AS dt_exposed_through
    FROM
        period_contexts AS pctx
    CROSS JOIN
        stats_labels AS stl
    LEFT JOIN
        agg_exposed AS aex
            ON aex.period_type = pctx.period_type
            AND aex.period_start = pctx.period_start
            AND aex.business_context = pctx.business_context
    LEFT JOIN
        agg_available AS aav
            ON aav.business_context = pctx.business_context

    UNION ALL

    /* Standalone daily snapshot of published inventory, keyed on the run date rather
       than on a reporting period. Later runs land in a different partition, so these
       rows are never rewritten and accumulate a real history of available inventory —
       something the week and month rows cannot carry, because their available columns
       are refreshed to the latest snapshot on every rebuild. */
    SELECT
        aav.business_context,
        'available' AS period_type,
        stl.stats,
        CAST(NULL AS DOUBLE) AS exposed_price_raw,
        aav.price_stats[stl.stats_position] AS available_listings_price_raw,
        CAST(NULL AS DOUBLE) AS exposed_impressions_age_days_raw,
        aav.age_stats[stl.stats_position] AS available_listings_age_days_raw,
        CAST(NULL AS BIGINT) AS n_exposed,
        aav.n_available,
        TRUE AS is_period_complete,
        CURRENT_DATE() AS period_start,
        CURRENT_DATE() AS period_end,
        CAST(NULL AS DATE) AS dt_exposed_through
    FROM
        agg_available AS aav
    CROSS JOIN
        stats_labels AS stl
)

SELECT
    business_context,
    period_type,
    stats,
    CAST(ROUND(exposed_price_raw) AS BIGINT) AS exposed_price,
    CAST(ROUND(available_listings_price_raw) AS BIGINT) AS available_listings_price,
    CONCAT('R$ ', TRANSLATE(FORMAT_NUMBER(exposed_price_raw, 2), '.,', ',.')) AS exposed_price_brl,
    CONCAT('R$ ', TRANSLATE(FORMAT_NUMBER(available_listings_price_raw, 2), '.,', ',.')) AS available_listings_price_brl,
    CAST(ROUND(exposed_impressions_age_days_raw) AS BIGINT) AS exposed_impressions_age_days,
    CAST(ROUND(available_listings_age_days_raw) AS BIGINT) AS available_listings_age_days,
    n_exposed,
    n_available,
    is_period_complete,
    period_start,
    period_end,
    dt_exposed_through,
    CURRENT_DATE() AS dt_available_snapshot,
    YEAR(period_start) AS year,
    MONTH(period_start) AS month,
    DAY(period_start) AS day
FROM
    distribution
