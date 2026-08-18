-- Monthly business metrics pivoted by tenant prospect activity_segment, business context, concierge-prospect status, and cohort window (4w / 8w).
-- Grain: one row per activation month, business context, concierge-prospect status, cohort window, and metric name.

WITH activity_months_to_process AS (
    SELECT DISTINCT
        dt_activation_month
    FROM
        datalake_search.tenant_prospect_segmentation
    WHERE
        dt_partition BETWEEN DATE('{start_date}') AND DATE('{end_date}')
),

activity_month_scope AS (
    SELECT
        s.dt_activation_month,
        s.id_user,
        s.business_context,
        bp.ts_activation,
        bp.dt_window_4w_end,
        bp.dt_window_8w_end,
        bp.segment_type,
        bp.is_concierge_prospect,
        s.dt_partition,
        s.is_os_8w,
        s.is_os_4w,
        s.sum_interactions_8w,
        s.sum_interactions_4w,
        s.sum_search_8w,
        s.sum_search_4w,
        s.sum_search_with_lpv_8w,
        s.sum_search_with_lpv_4w,
        s.sum_search_lpv_8w,
        s.sum_search_lpv_4w,
        s.sum_listing_spv_8w,
        s.sum_listing_spv_4w,
        s.sum_lpv_8w,
        s.sum_lpv_4w,
        s.sum_schedule_8w,
        s.sum_schedule_4w,
        s.sum_visit_8w,
        s.sum_visit_4w,
        s.id_house_partition_spv_ts,
        s.id_house_partition_lpv_ts,
        s.id_house_partition_vb_ts
    FROM
        datalake_search.tenant_prospect_segmentation AS s
    INNER JOIN
        activity_months_to_process AS m
        ON s.dt_activation_month = m.dt_activation_month
    INNER JOIN
        datalake_search.tenant_prospect_base AS bp
        ON s.id_user = bp.id_user
        AND s.dt_activation_month = bp.dt_activation_month
        AND s.business_context = bp.business_context
        AND s.ts_activation = bp.ts_activation
        AND s.segment_type = bp.segment_type
        AND s.is_concierge_prospect = bp.is_concierge_prospect
),

activity_month_aggregation AS (
    SELECT
        dt_activation_month,
        id_user,
        business_context,
        segment_type,
        is_concierge_prospect,
        dt_window_4w_end,
        dt_window_8w_end,
        MAX(is_os_8w) AS is_os_8w,
        MAX(is_os_4w) AS is_os_4w,
        SUM(sum_interactions_8w) AS sum_interactions_8w,
        SUM(sum_interactions_4w) AS sum_interactions_4w,
        SUM(sum_search_8w) AS sum_search_8w,
        SUM(sum_search_4w) AS sum_search_4w,
        SUM(sum_search_with_lpv_8w) AS sum_search_with_lpv_8w,
        SUM(sum_search_with_lpv_4w) AS sum_search_with_lpv_4w,
        SUM(sum_search_lpv_8w) AS sum_search_lpv_8w,
        SUM(sum_search_lpv_4w) AS sum_search_lpv_4w,
        SUM(sum_listing_spv_8w) AS sum_listing_spv_8w,
        SUM(sum_listing_spv_4w) AS sum_listing_spv_4w,
        SUM(sum_lpv_8w) AS sum_lpv_8w,
        SUM(sum_lpv_4w) AS sum_lpv_4w,
        SUM(sum_schedule_8w) AS sum_schedule_8w,
        SUM(sum_schedule_4w) AS sum_schedule_4w,
        SUM(sum_visit_8w) AS sum_visit_8w,
        SUM(sum_visit_4w) AS sum_visit_4w
    FROM
        activity_month_scope s
    GROUP BY
        id_user,
        business_context,
        segment_type,
        is_concierge_prospect,
        dt_activation_month,
        dt_window_4w_end,
        dt_window_8w_end
),

exploded_houses_spv AS (
    SELECT
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month,
        spv_event.id_house AS id_house,
        spv_event.has_lpv AS has_lpv,
        spv_event.is_4w AS is_4w
    FROM
        activity_month_scope AS s
    LATERAL VIEW explode(COALESCE(s.id_house_partition_spv_ts, array())) spv_events AS spv_event
),

agg_houses_spv AS (
    SELECT
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month,
        id_house,
        is_4w,
        MAX(has_lpv) AS has_lpv
    FROM
        exploded_houses_spv
    GROUP BY
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month,
        id_house,
        is_4w
),

distinct_houses_spv AS (
    SELECT
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month,
        COUNT(DISTINCT id_house) AS sum_dist_listing_spv_8w,
        COUNT(DISTINCT
            CASE
                WHEN is_4w = 1 THEN id_house
            END
        ) AS sum_dist_listing_spv_4w,
        COUNT(DISTINCT
            CASE
                WHEN has_lpv = 1 THEN id_house
            END
        ) AS sum_dist_listing_spv_with_lpv_8w,
        COUNT(DISTINCT
            CASE
                WHEN has_lpv = 1 AND is_4w = 1 THEN id_house
            END
        ) AS sum_dist_listing_spv_with_lpv_4w
    FROM
        agg_houses_spv
    GROUP BY
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month
),

exploded_houses_lpv AS (
    SELECT
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month,
        lpv_event.id_house AS id_house,
        lpv_event.ts_event AS ts_event,
        lpv_event.is_4w AS is_4w
    FROM
        activity_month_scope AS s
    LATERAL VIEW explode(COALESCE(s.id_house_partition_lpv_ts, array())) lpv_events AS lpv_event
),

agg_houses_lpv AS (
    SELECT
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month,
        id_house,
        MIN(ts_event) AS id_house_first_lpv_ts,
        MAX(is_4w) AS is_4w
    FROM
        exploded_houses_lpv
    GROUP BY
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month,
        id_house
),

distinct_houses_lpv AS (
    SELECT
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month,
        COUNT(DISTINCT id_house) AS sum_dist_listing_lpv_8w,
        COUNT(DISTINCT
            CASE
                WHEN is_4w = 1 THEN id_house
            END
        ) AS sum_dist_listing_lpv_4w
    FROM
        agg_houses_lpv
    GROUP BY
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month
),

exploded_houses_vb AS (
    SELECT
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month,
        vb_event.id_house AS id_house,
        vb_event.ts_event AS id_house_first_vb_ts,
        vb_event.is_4w AS is_4w
    FROM
        activity_month_scope AS s
    LATERAL VIEW explode(COALESCE(s.id_house_partition_vb_ts, array())) vb_events AS vb_event
),


vb_after_lpv AS (
    SELECT
        vb.id_user,
        vb.business_context,
        vb.is_concierge_prospect,
        vb.dt_activation_month,
        vb.id_house,
        vb.is_4w
    FROM
        exploded_houses_vb vb
    INNER JOIN agg_houses_lpv lpv
        ON vb.id_user = lpv.id_user
        AND vb.business_context = lpv.business_context
        AND vb.is_concierge_prospect = lpv.is_concierge_prospect
        AND vb.dt_activation_month = lpv.dt_activation_month
        AND vb.id_house = lpv.id_house
        AND vb.id_house_first_vb_ts > lpv.id_house_first_lpv_ts
),

vb_after_lpv_agg AS (
    SELECT
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month,
        COUNT(DISTINCT id_house) AS sum_dist_listing_lpv_vb_8w,
        COUNT(DISTINCT CASE WHEN is_4w = 1 THEN id_house END) AS sum_dist_listing_lpv_vb_4w
    FROM
        vb_after_lpv
    GROUP BY
        id_user,
        business_context,
        is_concierge_prospect,
        dt_activation_month
),

activity_month_aggregation_with_lpv_vb AS (
    SELECT
        ama.id_user,
        ama.business_context,
        ama.segment_type,
        ama.is_concierge_prospect,
        ama.dt_activation_month,
        ama.dt_window_4w_end,
        ama.dt_window_8w_end,
        ama.is_os_8w,
        ama.is_os_4w,
        ama.sum_interactions_8w,
        ama.sum_interactions_4w,
        ama.sum_search_8w,
        ama.sum_search_4w,
        ama.sum_search_with_lpv_8w,
        ama.sum_search_with_lpv_4w,
        ama.sum_search_lpv_8w,
        ama.sum_search_lpv_4w,
        ama.sum_listing_spv_8w,
        ama.sum_listing_spv_4w,
        COALESCE(spv.sum_dist_listing_spv_8w, 0) AS sum_dist_listing_spv_8w,
        COALESCE(spv.sum_dist_listing_spv_4w, 0) AS sum_dist_listing_spv_4w,
        ama.sum_lpv_8w,
        ama.sum_lpv_4w,
        COALESCE(lpv.sum_dist_listing_lpv_8w, 0) AS sum_dist_listing_lpv_8w,
        COALESCE(lpv.sum_dist_listing_lpv_4w, 0) AS sum_dist_listing_lpv_4w,
        ama.sum_visit_8w,
        ama.sum_visit_4w,
        ama.sum_schedule_8w,
        ama.sum_schedule_4w,
        COALESCE(lpv_vb.sum_dist_listing_lpv_vb_8w, 0) AS sum_dist_listing_lpv_vb_8w,
        COALESCE(lpv_vb.sum_dist_listing_lpv_vb_4w, 0) AS sum_dist_listing_lpv_vb_4w,
        COALESCE(spv.sum_dist_listing_spv_with_lpv_8w, 0) AS sum_dist_listing_spv_with_lpv_8w,
        COALESCE(spv.sum_dist_listing_spv_with_lpv_4w, 0) AS sum_dist_listing_spv_with_lpv_4w
    FROM
        activity_month_aggregation AS ama
    LEFT JOIN
        distinct_houses_spv AS spv
        ON ama.id_user = spv.id_user
        AND ama.business_context = spv.business_context
        AND ama.is_concierge_prospect = spv.is_concierge_prospect
        AND ama.dt_activation_month = spv.dt_activation_month
    LEFT JOIN
        distinct_houses_lpv AS lpv
        ON ama.id_user = lpv.id_user
        AND ama.business_context = lpv.business_context
        AND ama.is_concierge_prospect = lpv.is_concierge_prospect
        AND ama.dt_activation_month = lpv.dt_activation_month
    LEFT JOIN
        vb_after_lpv_agg AS lpv_vb
        ON ama.id_user = lpv_vb.id_user
        AND ama.business_context = lpv_vb.business_context
        AND ama.is_concierge_prospect = lpv_vb.is_concierge_prospect
        AND ama.dt_activation_month = lpv_vb.dt_activation_month
),

cohort_and_activity_segmentation AS (
    SELECT
        dt_activation_month,
        id_user,
        business_context,
        segment_type,
        is_concierge_prospect,
        CASE
            WHEN sum_interactions_8w > 10 THEN 'qualified_search_active'
            WHEN sum_interactions_8w >= 1 AND sum_interactions_8w <= 10 THEN 'low_search_active'
            WHEN sum_interactions_8w = 0 AND (sum_lpv_8w >= 1 OR sum_schedule_8w >= 1) THEN 'active_no_search'
            WHEN sum_interactions_8w = 0 AND sum_lpv_8w = 0 AND sum_schedule_8w = 0 THEN 'inactive'
        END AS activity_segment,
        '8w' AS cohort_window,
        is_os_8w AS is_os,
        sum_interactions_8w AS sum_interactions,
        sum_search_8w AS sum_search,
        sum_search_with_lpv_8w AS sum_search_with_lpv,
        sum_search_lpv_8w AS sum_search_lpv,
        sum_listing_spv_8w AS sum_listing_spv,
        sum_dist_listing_spv_8w AS sum_dist_listing_spv,
        sum_lpv_8w AS sum_lpv,
        sum_dist_listing_lpv_8w AS sum_dist_listing_lpv,
        sum_visit_8w AS sum_visit,
        sum_dist_listing_lpv_vb_8w AS sum_dist_listing_lpv_vb,
        sum_dist_listing_spv_with_lpv_8w AS sum_dist_listing_spv_with_lpv
    FROM
        activity_month_aggregation_with_lpv_vb
    UNION ALL
    SELECT
        dt_activation_month,
        id_user,
        business_context,
        segment_type,
        is_concierge_prospect,
        CASE
            WHEN sum_interactions_4w > 10 THEN 'qualified_search_active'
            WHEN sum_interactions_4w >= 1 AND sum_interactions_4w <= 10 THEN 'low_search_active'
            WHEN sum_interactions_4w = 0 AND (sum_lpv_4w >= 1 OR sum_schedule_4w >= 1) THEN 'active_no_search'
            WHEN sum_interactions_4w = 0 AND sum_lpv_4w = 0 AND sum_schedule_4w = 0 THEN 'inactive'
        END AS activity_segment,
        '4w' AS cohort_window,
        is_os_4w AS is_os,
        sum_interactions_4w AS sum_interactions,
        sum_search_4w AS sum_search,
        sum_search_with_lpv_4w AS sum_search_with_lpv,
        sum_search_lpv_4w AS sum_search_lpv,
        sum_listing_spv_4w AS sum_listing_spv,
        sum_dist_listing_spv_4w AS sum_dist_listing_spv,
        sum_lpv_4w AS sum_lpv,
        sum_dist_listing_lpv_4w AS sum_dist_listing_lpv,
        sum_visit_4w AS sum_visit,
        sum_dist_listing_lpv_vb_4w AS sum_dist_listing_lpv_vb,
        sum_dist_listing_spv_with_lpv_4w AS sum_dist_listing_spv_with_lpv
    FROM
        activity_month_aggregation_with_lpv_vb
),

activity_segment_metrics AS (
    SELECT
        dt_activation_month,
        business_context,
        segment_type,
        is_concierge_prospect,
        cohort_window,
        activity_segment,
        COUNT(id_user) AS num_active_tenant_prospects,
        SUM(sum_interactions) / NULLIF(COUNT(id_user), 0) AS avg_int_per_active_tenant_prospect,
        SUM(sum_search) / NULLIF(COUNT(id_user), 0) AS avg_spv_per_active_tenant_prospect,
        SUM(sum_lpv) / NULLIF(COUNT(id_user), 0) AS avg_lpv_per_active_tenant_prospect,
        SUM(sum_dist_listing_spv) / NULLIF(COUNT(id_user), 0) AS avg_dist_listing_spv_per_active_tenant_prospect,
        SUM(sum_dist_listing_spv) / NULLIF(SUM(sum_listing_spv), 0) AS pct_dist_listing_on_spv,
        SUM(sum_dist_listing_lpv) / NULLIF(COUNT(id_user), 0) AS avg_dist_listing_lpv_per_active_tenant_prospect,
        SUM(sum_dist_listing_lpv) / NULLIF(SUM(sum_lpv), 0) AS pct_dist_listing_lpv,
        SUM(sum_visit) / NULLIF(COUNT(id_user), 0) AS avg_vb_per_active_tenant_prospect
    FROM
        cohort_and_activity_segmentation
    WHERE
        activity_segment IS NOT NULL
    GROUP BY
        dt_activation_month,
        business_context,
        segment_type,
        is_concierge_prospect,
        cohort_window,
        activity_segment
),

activity_segment_long_format AS (
    SELECT
        dt_activation_month,
        business_context,
        segment_type,
        is_concierge_prospect,
        cohort_window,
        activity_segment,
        stacked.metric,
        stacked.value
    FROM
        activity_segment_metrics
    LATERAL VIEW STACK(
        9,
        'num_active_tenant_prospects',
        CAST(num_active_tenant_prospects AS DOUBLE),
        'avg_int_per_active_tenant_prospect',
        avg_int_per_active_tenant_prospect,
        'avg_spv_per_active_tenant_prospect',
        avg_spv_per_active_tenant_prospect,
        'avg_lpv_per_active_tenant_prospect',
        avg_lpv_per_active_tenant_prospect,
        'avg_dist_listing_spv_per_active_tenant_prospect',
        avg_dist_listing_spv_per_active_tenant_prospect,
        'pct_dist_listing_on_spv',
        pct_dist_listing_on_spv,
        'avg_dist_listing_lpv_per_active_tenant_prospect',
        avg_dist_listing_lpv_per_active_tenant_prospect,
        'pct_dist_listing_lpv',
        pct_dist_listing_lpv,
        'avg_vb_per_active_tenant_prospect',
        avg_vb_per_active_tenant_prospect
    ) stacked AS metric, value
),

overall_metrics AS (
    SELECT
        dt_activation_month,
        business_context,
        segment_type,
        is_concierge_prospect,
        cohort_window,
        COUNT(id_user) AS num_active_tenant_prospects,
        COUNT(CASE WHEN activity_segment = 'qualified_search_active' THEN id_user END) AS num_qualified_search_active_tenant_prospects,
        COUNT(CASE WHEN activity_segment = 'low_search_active' THEN id_user END) AS num_low_search_active_tenant_prospects,
        COUNT(CASE WHEN activity_segment = 'active_no_search' THEN id_user END) AS num_active_no_search_tenant_prospects,
        SUM(sum_search_lpv) / NULLIF(SUM(sum_interactions), 0) AS avg_lpv_per_int,
        SUM(sum_search_lpv) / NULLIF(SUM(sum_search), 0) AS avg_lpv_per_spv,
        SUM(sum_search_with_lpv) / NULLIF(SUM(sum_search), 0) AS pct_search_with_lpv,
        SUM(sum_visit) / NULLIF(SUM(sum_lpv), 0) AS avg_vb_per_lpv,
        SUM(sum_dist_listing_lpv_vb) / NULLIF(SUM(sum_dist_listing_lpv), 0) AS pct_vb_per_dist_lpv,
        SUM(sum_visit) / NULLIF(SUM(sum_interactions), 0) AS avg_vb_per_int,
        SUM(sum_visit) / NULLIF(SUM(sum_search), 0) AS avg_vb_per_spv,
        SUM(sum_dist_listing_spv_with_lpv) / NULLIF(SUM(sum_dist_listing_spv), 0) AS discovery_rate,
        COUNT(CASE WHEN (sum_visit >= 3) OR (is_os = 1 AND sum_visit >= 1) THEN id_user END) / NULLIF(COUNT(id_user), 0) AS bes
    FROM
        cohort_and_activity_segmentation
    GROUP BY
        dt_activation_month,
        business_context,
        segment_type,
        is_concierge_prospect,
        cohort_window
),

overall_metrics_all AS (
    SELECT
        dt_activation_month,
        business_context,
        segment_type,
        is_concierge_prospect,
        cohort_window,
        num_active_tenant_prospects,
        avg_lpv_per_int,
        avg_lpv_per_spv,
        pct_search_with_lpv,
        avg_vb_per_lpv,
        pct_vb_per_dist_lpv,
        avg_vb_per_int,
        avg_vb_per_spv,
        (num_qualified_search_active_tenant_prospects + num_low_search_active_tenant_prospects)
        / NULLIF(
            num_qualified_search_active_tenant_prospects
            + num_low_search_active_tenant_prospects
            + num_active_no_search_tenant_prospects,
            0
        ) AS search_participation_rate,
        num_qualified_search_active_tenant_prospects
        / NULLIF(
            num_qualified_search_active_tenant_prospects + num_low_search_active_tenant_prospects,
            0
        ) AS qualified_penetration,
        discovery_rate,
        bes
    FROM
        overall_metrics
),

overall_metrics_long_format AS (
    SELECT
        dt_activation_month,
        business_context,
        segment_type,
        is_concierge_prospect,
        cohort_window,
        'overall' AS activity_segment,
        stacked.metric,
        stacked.value
    FROM
        overall_metrics_all
    LATERAL VIEW STACK(
        12,
        'num_active_tenant_prospects',
        CAST(num_active_tenant_prospects AS DOUBLE),
        'avg_lpv_per_int',
        avg_lpv_per_int,
        'avg_lpv_per_spv',
        avg_lpv_per_spv,
        'pct_search_with_lpv',
        pct_search_with_lpv,
        'avg_vb_per_lpv',
        avg_vb_per_lpv,
        'pct_vb_per_dist_lpv',
        pct_vb_per_dist_lpv,
        'avg_vb_per_int',
        avg_vb_per_int,
        'avg_vb_per_spv',
        avg_vb_per_spv,
        'search_participation_rate',
        search_participation_rate,
        'qualified_penetration',
        qualified_penetration,
        'discovery_rate',
        discovery_rate,
        'bes',
        CAST(bes AS DOUBLE)
    ) stacked AS metric, value
),

metrics_long_format AS (
    SELECT
        dt_activation_month,
        business_context,
        segment_type,
        is_concierge_prospect,
        cohort_window,
        activity_segment,
        metric,
        value
    FROM
        activity_segment_long_format
    UNION ALL
    SELECT
        dt_activation_month,
        business_context,
        segment_type,
        is_concierge_prospect,
        cohort_window,
        activity_segment,
        metric,
        value
    FROM
        overall_metrics_long_format
),

metrics_pivoted AS (
    SELECT
        dt_activation_month,
        business_context,
        segment_type,
        is_concierge_prospect,
        cohort_window,
        metric,
        MAX(
            CASE
                WHEN activity_segment = 'overall' THEN value
            END
        ) AS overall,
        MAX(
            CASE
                WHEN activity_segment = 'qualified_search_active' THEN value
            END
        ) AS qualified_search_active,
        MAX(
            CASE
                WHEN activity_segment = 'low_search_active' THEN value
            END
        ) AS low_search_active,
        MAX(
            CASE
                WHEN activity_segment = 'active_no_search' THEN value
            END
        ) AS active_no_search,
        MAX(
            CASE
                WHEN activity_segment = 'inactive' THEN value
            END
        ) AS inactive,
        YEAR(dt_activation_month) AS year,
        MONTH(dt_activation_month) AS month,
        DAY(dt_activation_month) AS day
    FROM
        metrics_long_format
    GROUP BY
        dt_activation_month,
        business_context,
        segment_type,
        is_concierge_prospect,
        cohort_window,
        metric
)
SELECT
    dt_activation_month,
    business_context,
    segment_type,
    is_concierge_prospect,
    cohort_window,
    metric,
    overall,
    qualified_search_active,
    low_search_active,
    active_no_search,
    inactive,
    year,
    month,
    day
FROM
    metrics_pivoted
