WITH date_scope AS (
    SELECT
        dt_partition
    FROM
        (SELECT EXPLODE(SEQUENCE(DATE('{start_date}'), DATE('{end_date}'))) AS dt_partition)
),

bp_daily_scope AS (
    SELECT
        date_scope.dt_partition,
        bp.id_user,
        bp.business_context,
        bp.is_concierge_prospect,
        bp.dt_activation_month,
        bp.ts_bp_activation,
        bp.dt_window_4w_end,
        bp.dt_window_8w_end
    FROM
        datalake_search.buyer_prospect_base AS bp
    INNER JOIN
        date_scope
            ON date_scope.dt_partition >= DATE(bp.ts_bp_activation)
            AND date_scope.dt_partition <= bp.dt_window_8w_end
),

parsed_searches AS (
    SELECT
        MAKE_DATE(year, month, day) AS dt_partition,
        ts_event,
        GET_JSON_OBJECT(ids, '$.id_session') AS id_session,
        GET_JSON_OBJECT(ids, '$.id_search') AS id_search,
        GET_JSON_OBJECT(ids, '$.id_house') AS id_house,
        GET_JSON_OBJECT(ids, '$.id_user') AS id_user
    FROM
        datalake_search.search_impressions
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{start_date}') AND DATE('{end_date}')
        AND LOWER(GET_JSON_OBJECT(dimensions, '$.business_context')) = 'sale'
        AND GET_JSON_OBJECT(ids, '$.id_user') IS NOT NULL
        AND GET_JSON_OBJECT(ids, '$.id_session') IS NOT NULL
        AND GET_JSON_OBJECT(ids, '$.id_search') IS NOT NULL
),

parsed_lpv AS (
    SELECT
        MAKE_DATE(year, month, day) AS dt_partition,
        id_user,
        ts_event,
        id_session,
        ep_house_id,
        GET_JSON_OBJECT(event_properties, '$.search_id') AS id_search,
        ROW_NUMBER() OVER (
            PARTITION BY
                MAKE_DATE(year, month, day),
                id_session,
                GET_JSON_OBJECT(event_properties, '$.search_id'),
                ep_house_id,
                id_user
            ORDER BY
                ts_event ASC
        ) AS rn
    FROM
        datalake_amplitude_clean.170698_listing_page_viewed_events
    WHERE
        id_user IS NOT NULL
        AND ep_house_id IS NOT NULL
        AND id_session IS NOT NULL
        AND LOWER(GET_JSON_OBJECT(event_properties, '$.business_context')) = 'sale'
        AND MAKE_DATE(year, month, day) BETWEEN DATE('{start_date}') AND DATE('{end_date}')
),

search_with_lpv AS (
    SELECT DISTINCT
        s.dt_partition,
        s.id_user,
        s.ts_event,
        s.id_session,
        s.id_search,
        s.id_house,
        lpv.ep_house_id as id_house_search_lpv,
        CASE
            WHEN lpv.id_search IS NOT NULL THEN 1
            ELSE 0
        END AS is_listing_with_lpv
    FROM
        parsed_searches AS s
    LEFT JOIN
        parsed_lpv AS lpv
            ON lpv.rn = 1
            AND s.dt_partition = lpv.dt_partition
            AND s.id_session = lpv.id_session
            AND s.id_search = lpv.id_search
            AND s.id_house = lpv.ep_house_id
            AND s.id_user = lpv.id_user
),

parsed_schedule AS (
    SELECT
        MAKE_DATE(year, month, day) AS dt_partition,
        id_user,
        ts_event
    FROM
        datalake_amplitude_clean.170698_schedule_page_viewed_events
    WHERE
        id_user IS NOT NULL
        AND ep_house_id IS NOT NULL
        AND LOWER(business_context) = 'sale'
        AND MAKE_DATE(year, month, day) BETWEEN DATE('{start_date}') AND DATE('{end_date}')
),

visits_booked AS (
    SELECT
        DISTINCT
        DATE(ts_first_booking_created) AS dt_partition,
        id_buyer AS id_user,
        id_house,
        DATE_TRUNC('second', ts_first_booking_created + INTERVAL 500 MILLISECONDS) AS ts_event
    FROM
        datalake_sale_flows.sale_flow
    WHERE
        flow_type LIKE '%VB%'
        AND id_buyer IS NOT NULL
        AND id_house IS NOT NULL
        AND DATE(ts_first_booking_created) BETWEEN DATE('{start_date}') AND DATE('{end_date}')
),

events_unioned AS (
    SELECT
        dt_partition,
        'search' AS event_type,
        id_user,
        ts_event,
        id_session,
        id_search,
        id_house,
        is_listing_with_lpv
    FROM
        search_with_lpv
    UNION ALL
    SELECT
        dt_partition,
        'lpv' AS event_type,
        id_user,
        ts_event,
        CAST(NULL AS STRING) AS id_session,
        CAST(NULL AS STRING) AS id_search,
        ep_house_id as id_house,
        CAST(NULL AS INT) AS is_listing_with_lpv
    FROM
        parsed_lpv
    UNION ALL
    SELECT
        dt_partition,
        'schedule' AS event_type,
        id_user,
        ts_event,
        CAST(NULL AS STRING) AS id_session,
        CAST(NULL AS STRING) AS id_search,
        CAST(NULL AS STRING) AS id_house,
        CAST(NULL AS INT) AS is_listing_with_lpv
    FROM
        parsed_schedule
    UNION ALL
    SELECT
        dt_partition,
        'visit' AS event_type,
        id_user,
        ts_event,
        CAST(NULL AS STRING) AS id_session,
        CAST(NULL AS STRING) AS id_search,
        id_house,
        CAST(NULL AS INT) AS is_listing_with_lpv
    FROM
        visits_booked
),

buyer_activity AS (
    SELECT
        bp.dt_partition,
        bp.dt_activation_month,
        bp.business_context,
        bp.id_user,
        bp.dt_window_4w_end,
        eu.event_type,
        eu.ts_event,
        eu.id_session,
        eu.id_search,
        eu.id_house,
        eu.is_listing_with_lpv,
        CAST(
            eu.ts_event >= bp.ts_bp_activation
            AND eu.ts_event < DATE_ADD(bp.dt_window_4w_end, 1)
            AS INT
        ) AS is_4w
    FROM
        bp_daily_scope AS bp
    INNER JOIN
        events_unioned AS eu
            ON eu.dt_partition = bp.dt_partition
            AND eu.id_user = bp.id_user
            AND eu.ts_event >= bp.ts_bp_activation
            AND eu.ts_event < DATE_ADD(bp.dt_window_8w_end, 1)
),

daily_listing_lpv AS (
    SELECT
        dt_partition,
        dt_activation_month,
        business_context,
        id_user,
        id_house,
        MIN(ts_event) AS ts_event,
        MAX(is_4w) AS is_4w
    FROM
        buyer_activity
    WHERE
        event_type = 'lpv'
    GROUP BY
        dt_partition,
        dt_activation_month,
        business_context,
        id_user,
        id_house
),

agg_lpv_ts AS (
    SELECT
        dt_partition,
        dt_activation_month,
        business_context,
        id_user,
        COALESCE(
            collect_list(
                named_struct(
                    'id_house',
                    id_house,
                    'ts_event',
                    ts_event,
                    'is_4w',
                    is_4w
                )
            ),
            array()
        ) AS id_house_partition_lpv_ts
    FROM
        daily_listing_lpv
    GROUP BY
        dt_partition,
        dt_activation_month,
        business_context,
        id_user
),

agg_vb_ts AS (
    SELECT
        dt_partition,
        dt_activation_month,
        business_context,
        id_user,
        COALESCE(
            collect_list(
                named_struct(
                    'id_house',
                    id_house,
                    'ts_event',
                    ts_event,
                    'is_4w',
                    is_4w
                )
            ),
            array()
        ) AS id_house_partition_vb_ts
    FROM
        buyer_activity
    WHERE
        event_type = 'visit'
    GROUP BY
        dt_partition,
        dt_activation_month,
        business_context,
        id_user
),

daily_listing_spv AS (
    SELECT
        dt_partition,
        dt_activation_month,
        business_context,
        id_user,
        id_house,
        MIN(ts_event) AS ts_event,
        MAX(is_4w) AS is_4w,
        MAX(is_listing_with_lpv) AS has_lpv
    FROM
        buyer_activity
    WHERE
        event_type = 'search'
    GROUP BY
        dt_partition,
        dt_activation_month,
        business_context,
        id_user,
        id_house
),

agg_spv_ts AS (
    SELECT
        dt_partition,
        dt_activation_month,
        business_context,
        id_user,
        COALESCE(
            collect_list(
                named_struct(
                    'id_house',
                    id_house,
                    'ts_event',
                    ts_event,
                    'is_4w',
                    is_4w,
                    'has_lpv',
                    has_lpv
                )
            ),
            array()
        ) AS id_house_partition_spv_ts
    FROM
        daily_listing_spv
    GROUP BY
        dt_partition,
        dt_activation_month,
        business_context,
        id_user
),

agg_searches AS (
    SELECT
        dt_partition,
        dt_activation_month,
        business_context,
        id_user,
        COUNT(DISTINCT ts_event) AS sum_interactions_8w,
        COUNT(DISTINCT CASE
                WHEN is_4w = 1 THEN ts_event
            END) AS sum_interactions_4w,
        COUNT(DISTINCT id_search) AS sum_search_8w,
        COUNT(
            DISTINCT CASE
                WHEN is_4w = 1 THEN id_search
            END
        ) AS sum_search_4w,
        COUNT(
            DISTINCT CASE
                WHEN is_listing_with_lpv = 1 THEN id_search
            END
        ) AS sum_search_with_lpv_8w,
        COUNT(
            DISTINCT CASE
                WHEN is_listing_with_lpv = 1 AND is_4w = 1 THEN id_search
            END
        ) AS sum_search_with_lpv_4w,
        SUM(is_listing_with_lpv) AS sum_search_lpv_8w,
        SUM(is_4w * is_listing_with_lpv) AS sum_search_lpv_4w,
        COUNT(id_house) AS sum_listing_spv_8w,
        COUNT(
            CASE
                WHEN is_4w = 1 THEN id_house
            END
        ) AS sum_listing_spv_4w
    FROM
        buyer_activity
    WHERE
        event_type = 'search'
    GROUP BY
        dt_partition,
        dt_activation_month,
        business_context,
        id_user
),

agg_lpv AS (
    SELECT
        dt_partition,
        dt_activation_month,
        business_context,
        id_user,
        COUNT(ts_event) AS sum_lpv_8w,
        COUNT(
            CASE
                WHEN is_4w = 1 THEN ts_event
            END
        ) AS sum_lpv_4w
    FROM
        buyer_activity
    WHERE
        event_type = 'lpv'
    GROUP BY
        dt_partition,
        dt_activation_month,
        business_context,
        id_user
),

agg_schedule AS (
    SELECT
        dt_partition,
        dt_activation_month,
        business_context,
        id_user,
        COUNT(ts_event) AS sum_schedule_8w,
        COUNT(
            CASE
                WHEN is_4w = 1 THEN ts_event
            END
        ) AS sum_schedule_4w
    FROM
        buyer_activity
    WHERE
        event_type = 'schedule'
    GROUP BY
        dt_partition,
        dt_activation_month,
        business_context,
        id_user
),

agg_vb AS (
    SELECT
        dt_partition,
        dt_activation_month,
        business_context,
        id_user,
        COUNT(ts_event) AS sum_visit_8w,
        COUNT(
            CASE
                WHEN is_4w = 1 THEN ts_event
            END
        ) AS sum_visit_4w
    FROM
        buyer_activity
    WHERE
        event_type = 'visit'
    GROUP BY
        dt_partition,
        dt_activation_month,
        business_context,
        id_user
),

agg_activity AS (
    SELECT
        bp.dt_partition,
        bp.dt_activation_month,
        bp.ts_bp_activation,
        bp.dt_window_4w_end,
        bp.dt_window_8w_end,
        bp.business_context,
        bp.id_user,
        bp.is_concierge_prospect,
        COALESCE(ags.sum_interactions_8w, 0) AS sum_interactions_8w,
        COALESCE(ags.sum_interactions_4w, 0) AS sum_interactions_4w,
        COALESCE(ags.sum_search_8w, 0) AS sum_search_8w,
        COALESCE(ags.sum_search_4w, 0) AS sum_search_4w,
        COALESCE(ags.sum_search_with_lpv_8w, 0) AS sum_search_with_lpv_8w,
        COALESCE(ags.sum_search_with_lpv_4w, 0) AS sum_search_with_lpv_4w,
        COALESCE(ags.sum_search_lpv_8w, 0) AS sum_search_lpv_8w,
        COALESCE(ags.sum_search_lpv_4w, 0) AS sum_search_lpv_4w,
        COALESCE(ags.sum_listing_spv_8w, 0) AS sum_listing_spv_8w,
        COALESCE(ags.sum_listing_spv_4w, 0) AS sum_listing_spv_4w,
        COALESCE(alp.sum_lpv_8w, 0) AS sum_lpv_8w,
        COALESCE(alp.sum_lpv_4w, 0) AS sum_lpv_4w,
        COALESCE(ash.sum_schedule_8w, 0) AS sum_schedule_8w,
        COALESCE(ash.sum_schedule_4w, 0) AS sum_schedule_4w,
        COALESCE(avb.sum_visit_8w, 0) AS sum_visit_8w,
        COALESCE(avb.sum_visit_4w, 0) AS sum_visit_4w,
        COALESCE(aspt.id_house_partition_spv_ts, array()) AS id_house_partition_spv_ts,
        COALESCE(alpvt.id_house_partition_lpv_ts, array()) AS id_house_partition_lpv_ts,
        COALESCE(avbt.id_house_partition_vb_ts, array()) AS id_house_partition_vb_ts
    FROM
        bp_daily_scope AS bp
    LEFT JOIN
        agg_searches AS ags
            ON bp.dt_partition = ags.dt_partition
            AND bp.dt_activation_month = ags.dt_activation_month
            AND bp.id_user = ags.id_user
            AND bp.business_context = ags.business_context
    LEFT JOIN
        agg_lpv AS alp
            ON bp.dt_partition = alp.dt_partition
            AND bp.dt_activation_month = alp.dt_activation_month
            AND bp.id_user = alp.id_user
            AND bp.business_context = alp.business_context
    LEFT JOIN
        agg_schedule AS ash
            ON bp.dt_partition = ash.dt_partition
            AND bp.dt_activation_month = ash.dt_activation_month
            AND bp.id_user = ash.id_user
            AND bp.business_context = ash.business_context
    LEFT JOIN
        agg_vb AS avb
            ON bp.dt_partition = avb.dt_partition
            AND bp.dt_activation_month = avb.dt_activation_month
            AND bp.id_user = avb.id_user
            AND bp.business_context = avb.business_context
    LEFT JOIN
        agg_lpv_ts AS alpvt
            ON bp.dt_partition = alpvt.dt_partition
            AND bp.dt_activation_month = alpvt.dt_activation_month
            AND bp.business_context = alpvt.business_context
            AND bp.id_user = alpvt.id_user
    LEFT JOIN
        agg_vb_ts AS avbt
            ON bp.dt_partition = avbt.dt_partition
            AND bp.dt_activation_month = avbt.dt_activation_month
            AND bp.business_context = avbt.business_context
            AND bp.id_user = avbt.id_user
    LEFT JOIN
        agg_spv_ts AS aspt
            ON bp.dt_partition = aspt.dt_partition
            AND bp.dt_activation_month = aspt.dt_activation_month
            AND bp.business_context = aspt.business_context
            AND bp.id_user = aspt.id_user
)

SELECT
    dt_partition,
    id_user,
    business_context,
    is_concierge_prospect,
    dt_activation_month,
    ts_bp_activation,
    dt_window_4w_end,
    dt_window_8w_end,
    sum_interactions_8w,
    sum_interactions_4w,
    sum_search_8w,
    sum_search_4w,
    sum_search_with_lpv_8w,
    sum_search_with_lpv_4w,
    sum_search_lpv_8w,
    sum_search_lpv_4w,
    sum_listing_spv_8w,
    sum_listing_spv_4w,
    sum_lpv_8w,
    sum_lpv_4w,
    sum_schedule_8w,
    sum_schedule_4w,
    sum_visit_8w,
    sum_visit_4w,
    id_house_partition_spv_ts,
    id_house_partition_lpv_ts,
    id_house_partition_vb_ts,
    YEAR(dt_partition) AS year,
    MONTH(dt_partition) AS month,
    DAY(dt_partition) AS day
FROM
    agg_activity
