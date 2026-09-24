-- Daily eligibility snapshot for the concierge Shared/Retargeting LPV-ads use case.
-- Users who viewed a listing (CDP listing_page_viewed) coming from a shared link
-- (utm_source=shared, medium in copy_share/custom_share) or from facebook/criteo
-- retargeting, on a relative "yesterday", and who are not already engaged/suppressed.
--
-- Source of pageview is the CDP hub datalake_cdp_clean.user_tracking (fresh T-0/T-1,
-- egw_utm_* flattened), replacing the Amplitude listing_page_viewed events.
-- Privacy suppression reuses the shared datalake_search.concierge_privacy_user snapshot
-- (same pattern as enrich_concierge_placas_lpv_reproc), instead of parsing Privacy Hub.
--
-- Grain: lead user, prioritized listing, LPV date (relative yesterday). Partitions are the
-- run date (year, month, day). Raw phone/name are NOT persisted; downstream dispatch resolves
-- contact from id_person. group_ab carries the phone-based A/B cell (computed at build time).
--
-- PERF CHANGES (2026-09-15):
--   1. INNER JOIN on datalake_cdp.users — was LEFT JOIN with IS NOT NULL in WHERE, which
--      was effectively an inner join but prevented early filtering by the optimizer.
--      phone_number IS NOT NULL moved into the JOIN condition so the filter is applied before
--      the scan result is returned.
--   2. lpv_candidates CTE — wraps lpv_users (rn=1 only) and computes lag(dt_event) per user.
--      The 28-day cooldown (has_recent_prior_lpv) is now derived from prev_dt_lpv instead of
--      a self-join with a range predicate. Self-join on a range condition forces a sort-merge
--      join (O(N x 28) shuffle); lag() is a single O(N log N) sort pass.
--      Equivalent to the original Operations query (ads.sql) which used lag() + datediff > 28.
--   3. Concierge range join removed — concierge_outbound is already pre-filtered to
--      [current_date()-29, current_date()], which equals [yesterday-28, yesterday+1] for the
--      only rows that appear in the final output (dt_lpv = yesterday). Dropping the range
--      condition converts a non-equi join to a hash join.
-- PERF CHANGES (2026-09-16):
--   4. from_json() replaces 4× get_json_object() calls in lpv_events — event_properties is
--      parsed once per row into a typed struct; lpv_filtered dereferences struct fields.
--      get_json_object() re-parses the JSON string on every call; a single from_json() parse
--      is significantly cheaper at the scale of user_tracking.
WITH lpv_events AS (
    SELECT
        CAST(ut.id_user AS STRING)  AS id_user,
        ut.id_person,
        CAST(ut.ts_event AS DATE)   AS dt_event,
        -- [CHANGE 4] Parse event_properties once; downstream CTEs dereference struct fields.
        from_json(
            ut.event_properties,
            'STRUCT<business_context:STRING, utm_source:STRING, utm_medium:STRING, house_id:STRING>'
        )                           AS ep,
        ut.egw_utm_source,
        ut.egw_utm_medium,
        -- phone used only to derive the A/B cell; not persisted downstream
        du.phone_number             AS phone_for_ab
    FROM datalake_cdp_clean.user_tracking AS ut
    -- [CHANGE 1] INNER JOIN: was LEFT JOIN + WHERE du.phone_number IS NOT NULL, which
    -- silently turned into an inner join but blocked early filtering by the optimizer.
    INNER JOIN datalake_cdp.users AS du
        ON CAST(ut.id_user AS STRING) = du.id_user
        AND du.phone_number IS NOT NULL
    WHERE ut.event_name = 'listing_page_viewed'
        AND make_date(CAST(ut.year AS INT), CAST(ut.month AS INT), CAST(ut.day AS INT))
                BETWEEN date_add(current_date(), -30) AND current_date()
        AND CAST(ut.ts_event AS DATE)
                BETWEEN date_add(current_date(), -29) AND date_add(current_date(), -1)
        AND ut.id_user IS NOT NULL
),
lpv_filtered AS (
    -- Dereference the parsed struct; apply lower() and COALESCE here, once.
    SELECT
        id_user,
        id_person,
        dt_event,
        phone_for_ab,
        lower(ep.business_context)                                                  AS business_context,
        lower(COALESCE(NULLIF(ep.utm_source, ''), egw_utm_source))                 AS utm_source,
        lower(COALESCE(NULLIF(ep.utm_medium, ''), egw_utm_medium))                 AS utm_medium,
        CASE
            WHEN ep.house_id LIKE '%.%' THEN NULL
            ELSE CAST(ep.house_id AS BIGINT)
        END                                                                         AS id_house
    FROM lpv_events
    WHERE (
            lower(COALESCE(NULLIF(ep.utm_source, ''), egw_utm_source)) = 'shared'
            AND lower(COALESCE(NULLIF(ep.utm_medium, ''), egw_utm_medium)) IN ('copy_share', 'custom_share')
          )
       OR (
            lower(COALESCE(NULLIF(ep.utm_source, ''), egw_utm_source)) IN ('facebook', 'criteo')
            AND lower(COALESCE(NULLIF(ep.utm_medium, ''), egw_utm_medium)) IN ('retargeting', 'retargeting-retention')
          )
),
lpv_users_aux AS (
    SELECT
        id_user,
        id_person,
        dt_event,
        business_context,
        id_house,
        first(phone_for_ab) AS phone_for_ab,
        count(1) AS count_lpv
    FROM lpv_filtered
    GROUP BY 1, 2, 3, 4, 5
),
lpv_priced AS (
    SELECT
        lpv_aux.id_user,
        lpv_aux.id_person,
        lpv_aux.phone_for_ab,
        lpv_aux.dt_event,
        lpv_aux.business_context,
        lpv_aux.id_house,
        lpv_aux.count_lpv,
        house.city,
        house.region_name,
        house.id_user AS house_owner_id_user,
        house.id_user_registrant AS house_owner_id_user_registrant,
        CASE
            WHEN lpv_aux.business_context = 'rent' THEN house.rent + house.condo + house.iptu
            WHEN lpv_aux.business_context = 'sale' THEN house.sale_price
            ELSE NULL
        END AS price
    FROM lpv_users_aux AS lpv_aux
    LEFT JOIN datalake_ebdb_listing.house AS house
        ON lpv_aux.id_house = house.id
    WHERE lpv_aux.business_context IS NOT NULL
        AND house.city IS NOT NULL AND house.city <> ''
        AND house.region_name IS NOT NULL AND house.region_name <> '' AND house.region_name <> 'A Definir Em Campo'
        -- Only currently-available listings: the viewed house may have been sold /
        -- suspended / unpublished since the LPV, so require a published status and
        -- the flag matching the viewed context. Applied here (pre-ranking) so an
        -- unavailable top listing can't hide a qualifying available one. Note the
        -- ebdb house.status enum is Portuguese ('publicado', not 'PUBLISHED').
        AND house.status = 'publicado'
        AND (
            (lpv_aux.business_context = 'sale' AND house.is_for_sale = TRUE)
            OR (lpv_aux.business_context = 'rent' AND house.is_for_rent = TRUE)
        )
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
),
lpv_users AS (
    -- Apply the price-eligibility filter BEFORE ranking so the prioritized listing
    -- (sale over rent, most LPVs) is chosen among ELIGIBLE listings only. Otherwise a
    -- disqualified top listing (e.g. a sale below threshold) could hide a qualifying
    -- rent and drop the user entirely.
    SELECT
        id_user,
        id_person,
        phone_for_ab,
        dt_event,
        business_context,
        id_house,
        count_lpv,
        city,
        region_name,
        house_owner_id_user,
        house_owner_id_user_registrant,
        price,
        row_number() OVER (
            PARTITION BY id_user, dt_event
            ORDER BY lower(business_context) DESC, count_lpv DESC
        ) AS rn
    FROM lpv_priced
    WHERE price IS NOT NULL
        AND ((business_context = 'rent' AND price > 600) OR (business_context = 'sale' AND price > 150000))
),
-- [CHANGE 2] lpv_candidates: filters lpv_users to rn=1 (one row per user per day) and
-- computes prev_dt_lpv via lag(). This replaces the self-join with a range predicate in
-- final, restoring the same lag()-based approach used in the original Operations query.
-- lag() is a single sort pass; the self-join was a shuffle-heavy sort-merge range join.
lpv_candidates AS (
    SELECT
        *,
        lag(dt_event) OVER (PARTITION BY id_user ORDER BY dt_event) AS prev_dt_lpv
    FROM lpv_users
    WHERE rn = 1
),
concierge_outbound AS (
    SELECT DISTINCT
        CAST(m.ts_created AS DATE) AS dt_created,
        s.id_user
    FROM datalake_copilot_service_clean.message m
    JOIN datalake_copilot_service_clean.session s
        ON m.id_session = s.id
    WHERE m.channel = 'WHATSAPP_CONCIERGE_CHAT'
        AND CAST(m.ts_created AS DATE) BETWEEN date_add(current_date(), -29) AND current_date()
),
current_privacy_snapshot AS (
    -- concierge_privacy_user is person-grained (one row per id_person); join on id_person
    -- (same as enrich_concierge_placas_lpv_reproc) so a suppressed person is caught even
    -- when the LPV comes from a different linked id_user.
    SELECT
        id_person,
        is_concierge_privacy_suppressed
    FROM datalake_search.concierge_privacy_user
    WHERE year = YEAR(current_date())
        AND month = MONTH(current_date())
        AND day = DAY(current_date())
),
final AS (
    SELECT
        lpv.id_user,
        lpv.id_person,
        lpv.phone_for_ab,
        lpv.dt_event AS dt_lpv,
        lpv.id_house,
        lpv.business_context,
        lpv.city,
        lpv.region_name,
        lpv.price,
        lpv.count_lpv,
        lpv.house_owner_id_user,
        lpv.house_owner_id_user_registrant,
        max(CASE WHEN concierge.id_user IS NOT NULL THEN 1 ELSE 0 END) AS has_concierge,
        max(CASE WHEN COALESCE(priv.is_concierge_privacy_suppressed, FALSE) THEN 1 ELSE 0 END) AS is_suppressed,
        -- [CHANGE 2] 28-day cooldown via lag(): no self-join.
        -- prev_dt_lpv is the most recent prior eligible LPV day for this user (lag on rn=1 rows).
        -- If prev_dt_lpv is within 28 days, the user is in cooldown — same logic as the original
        -- Operations query: datediff(dt_lpv, prev_dt_lpv) <= 28.
        max(CASE WHEN lpv.prev_dt_lpv IS NOT NULL AND datediff(lpv.dt_event, lpv.prev_dt_lpv) <= 28 THEN 1 ELSE 0 END) AS has_recent_prior_lpv
    FROM lpv_candidates AS lpv
    -- [CHANGE 3] Equi-join only: the range condition (dt_created BETWEEN date_add(lpv.dt_event,-28)
    -- AND date_add(lpv.dt_event,1)) is redundant for the final output rows (dt_lpv=yesterday),
    -- because concierge_outbound is already filtered to [current_date()-29, current_date()],
    -- which equals [yesterday-28, yesterday+1]. Removing it converts the non-equi join to a
    -- hash join. For non-yesterday lpv rows the flag may differ from the original, but those
    -- rows are excluded by WHERE dt_lpv = date_add(current_date(), -1) below.
    LEFT JOIN concierge_outbound AS concierge
        ON lpv.id_user = CAST(concierge.id_user AS STRING)
    LEFT JOIN current_privacy_snapshot AS priv
        ON lpv.id_person = priv.id_person
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
)
SELECT
    id_user,
    id_person,
    id_house,
    CASE
        WHEN business_context = 'rent' THEN 'alugar'
        WHEN business_context = 'sale' THEN 'comprar'
        ELSE NULL
    END AS business_context,
    city,
    region_name,
    price,
    CASE
        WHEN price <= 10000   THEN FLOOR(price / 100.0)    * 100
        WHEN price <= 100000  THEN FLOOR(price / 1000.0)   * 1000
        WHEN price <= 1000000 THEN FLOOR(price / 10000.0)  * 10000
        ELSE FLOOR(price / 100000.0) * 100000
    END AS price_arred,
    count_lpv,
    dt_lpv,
    CASE
        WHEN CAST(RIGHT(regexp_replace(phone_for_ab, '[^0-9]', ''), 3) AS INT) BETWEEN 0 AND 499 THEN 'treatment'
        WHEN CAST(RIGHT(regexp_replace(phone_for_ab, '[^0-9]', ''), 3) AS INT) BETWEEN 500 AND 999 THEN 'control'
        ELSE 'out_of_test'
    END AS group_ab,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM final
WHERE dt_lpv = date_add(current_date(), -1)
    AND id_user IS NOT NULL
    -- price not-null and rent/sale thresholds are enforced pre-ranking in lpv_users
    AND has_concierge = 0
    AND has_recent_prior_lpv = 0
    AND is_suppressed = 0
    AND (house_owner_id_user IS NULL OR CAST(house_owner_id_user AS STRING) <> id_user)
    AND (house_owner_id_user_registrant IS NULL OR CAST(house_owner_id_user_registrant AS STRING) <> id_user)
