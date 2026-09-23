WITH latest_filters AS (
    SELECT
        ranked.id_search_profile,
        ranked.filters_json,
        ranked.events_count,
        ranked.ts_updated
    FROM (
        SELECT
            id_search_profile,
            filters_json,
            events_count,
            ts_updated,
            ROW_NUMBER() OVER (
                PARTITION BY id_search_profile
                ORDER BY ts_updated DESC
            ) AS rn
        FROM
            datalake_house_listing_search_clean.search_profile_filters
    ) AS ranked
    WHERE
        ranked.rn = 1
),
cluster_snapshot AS (
    SELECT
        TRY_CAST(search_profile.id_profile_holder AS BIGINT) AS id_user,
        UPPER(TRIM(search_profile.business_context)) AS cost_type,
        latest_filters.events_count AS cluster_events_count,
        -- filters_json speaks RENT_PRICE / SALE_PRICE while business_context
        -- speaks RENT / SALE; normalize to the business_context vocabulary so
        -- cost_type has a single set of values downstream.
        CASE UPPER(TRIM(GET_JSON_OBJECT(latest_filters.filters_json, '$.cost.costType')))
            WHEN 'RENT_PRICE' THEN 'RENT'
            WHEN 'SALE_PRICE' THEN 'SALE'
        END AS cluster_cost_type,
        GET_JSON_OBJECT(latest_filters.filters_json, '$.address.city') AS cluster_city,
        GET_JSON_OBJECT(latest_filters.filters_json, '$.address.neighborhoods') AS cluster_neighborhoods,
        TRY_CAST(GET_JSON_OBJECT(latest_filters.filters_json, '$.cost.max') AS INT) AS cluster_max_price,
        TRY_CAST(GET_JSON_OBJECT(latest_filters.filters_json, '$.bedrooms.min') AS INT) AS cluster_bedrooms,
        latest_filters.ts_updated AS ts_profile_updated
    FROM
        latest_filters
    INNER JOIN
        datalake_house_listing_search_clean.search_profile
        ON latest_filters.id_search_profile = search_profile.id
    WHERE
        search_profile.profile_holder_type = 'USER'
        AND TRY_CAST(search_profile.id_profile_holder AS BIGINT) IS NOT NULL
),
ranked_cluster AS (
    SELECT
        ranked.id_user,
        ranked.cost_type,
        ranked.cluster_events_count,
        ranked.cluster_cost_type,
        ranked.cluster_city,
        ranked.cluster_neighborhoods,
        ranked.cluster_max_price,
        ranked.cluster_bedrooms,
        ranked.ts_profile_updated
    FROM (
        SELECT
            cluster_snapshot.*,
            ROW_NUMBER() OVER (
                PARTITION BY id_user
                ORDER BY cluster_events_count DESC, ts_profile_updated DESC
            ) AS rn
        FROM
            cluster_snapshot
    ) AS ranked
    WHERE
        ranked.rn = 1
),
trigger_history AS (
    SELECT
        id_user,
        SUM(CASE WHEN LOWER(action) LIKE '%lowintent%' OR LOWER(action) LIKE '%qualifiedlow%' THEN 1 ELSE 0 END) AS qty_low_lifetime,
        SUM(CASE WHEN LOWER(action) LIKE '%mediumintent%' OR LOWER(action) LIKE '%contactsubmission%' THEN 1 ELSE 0 END) AS qty_med_lifetime,
        SUM(CASE WHEN LOWER(action) LIKE '%highintent%' THEN 1 ELSE 0 END) AS qty_high_lifetime,
        SUM(CASE WHEN DATE(ts_sent) > DATE_SUB(CURRENT_DATE(), {days_lookback_7})
            AND (LOWER(action) LIKE '%lowintent%' OR LOWER(action) LIKE '%qualifiedlow%') THEN 1 ELSE 0 END) AS qty_low_7d,
        SUM(CASE WHEN DATE(ts_sent) > DATE_SUB(CURRENT_DATE(), {days_lookback_7})
            AND (LOWER(action) LIKE '%mediumintent%' OR LOWER(action) LIKE '%contactsubmission%') THEN 1 ELSE 0 END) AS qty_med_7d,
        SUM(CASE WHEN DATE(ts_sent) > DATE_SUB(CURRENT_DATE(), {days_lookback_7})
            AND LOWER(action) LIKE '%highintent%' THEN 1 ELSE 0 END) AS qty_high_7d,
        MAX(CASE WHEN LOWER(action) LIKE '%lowintent%' OR LOWER(action) LIKE '%qualifiedlow%' THEN ts_sent END) AS ts_last_low,
        MAX(CASE WHEN LOWER(action) LIKE '%mediumintent%' OR LOWER(action) LIKE '%contactsubmission%' THEN ts_sent END) AS ts_last_med,
        MAX(CASE WHEN LOWER(action) LIKE '%highintent%' THEN ts_sent END) AS ts_last_high,
        MAX(CASE WHEN action = 'ConciergeSharedLpvAdsTrigger' OR template = 'concierge_placas_agents_reproc_trigger' THEN ts_sent END) AS ts_last_shared_lpv_ads
    FROM
        datalake_jaiminho_clean.user_notifications
    WHERE
        UPPER(channel) = 'WHATSAPP'
        AND UPPER(status) IN ('READ', 'SENT', 'DELIVERED')
        AND LOWER(action) LIKE '%concierge%'
        AND id_user IS NOT NULL
    GROUP BY
        id_user
),
-- Blocked numbers have to be read separately from the send history above:
-- the 210xx codes live on error_code, not status, and they only ever appear on
-- rows whose status is a failure, which the delivered-only filter excludes.
-- Mirrors the blocked_users logic and 180-day window in concierge_users.
blocked_users AS (
    SELECT
        id_user,
        TRUE AS is_whatsapp_blocked
    FROM
        datalake_jaiminho_clean.user_notifications
    WHERE
        DATEDIFF(CURRENT_DATE(), MAKE_DATE(year, month, day)) <= 180
        AND UPPER(channel) = 'WHATSAPP'
        AND error_code IN (21002, 21004, 21007)
        AND id_user IS NOT NULL
    GROUP BY
        id_user
),
all_users AS (
    SELECT id_user FROM ranked_cluster
    UNION
    SELECT id_user FROM trigger_history
    UNION
    SELECT id_user FROM blocked_users
)
SELECT
    all_users.id_user,
    ranked_cluster.cluster_events_count,
    COALESCE(ranked_cluster.cluster_cost_type, ranked_cluster.cost_type) AS cost_type,
    ranked_cluster.cluster_city,
    ranked_cluster.cluster_neighborhoods,
    ranked_cluster.cluster_max_price,
    ranked_cluster.cluster_bedrooms,
    ranked_cluster.ts_profile_updated,
    COALESCE(trigger_history.qty_low_7d, 0) AS qty_low_7d,
    COALESCE(trigger_history.qty_med_7d, 0) AS qty_med_7d,
    COALESCE(trigger_history.qty_high_7d, 0) AS qty_high_7d,
    COALESCE(trigger_history.qty_low_lifetime, 0) AS qty_low_lifetime,
    COALESCE(trigger_history.qty_med_lifetime, 0) AS qty_med_lifetime,
    COALESCE(trigger_history.qty_high_lifetime, 0) AS qty_high_lifetime,
    trigger_history.ts_last_low,
    trigger_history.ts_last_med,
    trigger_history.ts_last_high,
    CASE
        WHEN COALESCE(trigger_history.ts_last_high, TIMESTAMP('1970-01-01')) >= COALESCE(trigger_history.ts_last_med, TIMESTAMP('1970-01-01'))
            AND COALESCE(trigger_history.ts_last_high, TIMESTAMP('1970-01-01')) >= COALESCE(trigger_history.ts_last_low, TIMESTAMP('1970-01-01'))
            AND trigger_history.ts_last_high IS NOT NULL THEN 'HIGH'
        WHEN COALESCE(trigger_history.ts_last_med, TIMESTAMP('1970-01-01')) >= COALESCE(trigger_history.ts_last_low, TIMESTAMP('1970-01-01'))
            AND trigger_history.ts_last_med IS NOT NULL THEN 'MEDIUM'
        WHEN trigger_history.ts_last_low IS NOT NULL THEN 'LOW'
        ELSE NULL
    END AS last_template_family,
    trigger_history.ts_last_shared_lpv_ads,
    COALESCE(blocked_users.is_whatsapp_blocked, FALSE) AS is_whatsapp_blocked,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    all_users
LEFT JOIN
    ranked_cluster
    ON all_users.id_user = ranked_cluster.id_user
LEFT JOIN
    trigger_history
    ON all_users.id_user = trigger_history.id_user
LEFT JOIN
    blocked_users
    ON all_users.id_user = blocked_users.id_user
