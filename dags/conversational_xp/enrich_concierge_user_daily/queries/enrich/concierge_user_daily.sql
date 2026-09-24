-- Concierge audience rebuilt from the prepared concierge fact snapshots.
-- Deliberately reads no identity or eligibility source: this table carries the
-- behaviour signals and the intent decision only. Sending consumers join
-- identity and apply eligibility downstream. It does not read concierge_users;
-- it is the replacement for it.
WITH tof_facts AS (
    SELECT
        id_user,
        id_person,
        id_device,
        id_house_last_lpv,
        id_house_last_favorite,
        id_house_last_schedule,
        qty_search_sessions_7d,
        qty_search_sessions_60d,
        qty_search_rent_60d,
        qty_search_sale_60d,
        qty_lpv_3d,
        qty_houses_lpv_3d,
        array_id_house_top_5_lpv_3d,
        qty_favorites_1d,
        qty_favorites_7d,
        qty_schedule_page_1d,
        dt_last_search,
        ts_last_lpv
    FROM
        datalake_search.concierge_tof_events
    WHERE
        MAKE_DATE(year, month, day) = CURRENT_DATE()
),
hls_facts AS (
    SELECT
        id_user,
        cost_type,
        cluster_events_count,
        cluster_city,
        cluster_neighborhoods,
        cluster_max_price,
        cluster_bedrooms,
        ts_profile_updated,
        qty_low_7d,
        qty_med_7d,
        qty_high_7d,
        qty_low_lifetime,
        qty_med_lifetime,
        qty_high_lifetime,
        ts_last_low,
        ts_last_med,
        ts_last_high,
        last_template_family,
        ts_last_shared_lpv_ads,
        is_whatsapp_blocked
    FROM
        datalake_search.concierge_hls_user_daily
    WHERE
        MAKE_DATE(year, month, day) = CURRENT_DATE()
),
visit_facts AS (
    SELECT
        id_user,
        id_person,
        qty_visits_tomorrow,
        qty_visits_7d,
        qty_visits_canceled_1d,
        qty_visits_canceled_7d,
        qty_visits_rescheduled_1d,
        qty_visits_rescheduled_7d,
        id_house_next_visit,
        visit_code_next,
        ts_next_visit,
        id_house_last_canceled_1d,
        visit_code_last_canceled_1d,
        array_id_house_visit_open_or_done
    FROM
        datalake_search.concierge_visit_user_daily
    WHERE
        MAKE_DATE(year, month, day) = CURRENT_DATE()
),
offer_facts AS (
    SELECT
        id_user,
        has_rent_offer_1d,
        has_rent_offer_7d,
        id_house_last_offer,
        ts_last_offer
    FROM
        datalake_search.concierge_offer_user_daily
    WHERE
        MAKE_DATE(year, month, day) = CURRENT_DATE()
),
chat_facts AS (
    SELECT
        id_user,
        qty_chat_messages_7d,
        qty_chat_messages_28d,
        ts_last_chat_message
    FROM
        datalake_search.concierge_chat_history_user_daily
    WHERE
        MAKE_DATE(year, month, day) = CURRENT_DATE()
),
privacy_facts AS (
    SELECT
        id_user,
        id_person,
        snooze_concierge_status,
        tenant_message_ai_informative_status,
        ts_snooze_concierge_updated,
        ts_tenant_message_ai_informative_updated,
        is_snooze_concierge_active,
        is_tenant_message_ai_informative_withdrawn,
        is_concierge_privacy_suppressed
    FROM
        datalake_search.concierge_privacy_user
    WHERE
        MAKE_DATE(year, month, day) = CURRENT_DATE()
),
-- The audience is anyone with concierge-relevant behaviour today. Privacy is
-- deliberately not a spine member: a person who only ever expressed a snooze
-- purpose is not an audience candidate.
audience_spine AS (
    SELECT id_user FROM tof_facts
    UNION
    SELECT id_user FROM hls_facts
    UNION
    SELECT id_user FROM visit_facts
    UNION
    SELECT id_user FROM offer_facts
    UNION
    SELECT id_user FROM chat_facts
),
-- Resolve the person from behaviour first so privacy can be joined person to
-- person: concierge_privacy_user is one row per id_person keeping a single
-- representative id_user, so a user-key join alone would miss the linked
-- accounts of a snoozed person and read them as unsuppressed.
behaviour_person AS (
    SELECT
        audience_spine.id_user,
        COALESCE(tof_facts.id_person, visit_facts.id_person) AS id_person
    FROM
        audience_spine
    LEFT JOIN
        tof_facts
        ON audience_spine.id_user = tof_facts.id_user
    LEFT JOIN
        visit_facts
        ON audience_spine.id_user = visit_facts.id_user
),
privacy_resolved AS (
    SELECT
        behaviour_person.id_user,
        COALESCE(
            behaviour_person.id_person,
            privacy_by_user.id_person
        ) AS id_person,
        COALESCE(
            privacy_by_person.snooze_concierge_status,
            privacy_by_user.snooze_concierge_status
        ) AS snooze_concierge_status,
        COALESCE(
            privacy_by_person.tenant_message_ai_informative_status,
            privacy_by_user.tenant_message_ai_informative_status
        ) AS tenant_message_ai_informative_status,
        COALESCE(
            privacy_by_person.ts_snooze_concierge_updated,
            privacy_by_user.ts_snooze_concierge_updated
        ) AS ts_snooze_concierge_updated,
        COALESCE(
            privacy_by_person.ts_tenant_message_ai_informative_updated,
            privacy_by_user.ts_tenant_message_ai_informative_updated
        ) AS ts_tenant_message_ai_informative_updated,
        COALESCE(
            privacy_by_person.is_snooze_concierge_active,
            privacy_by_user.is_snooze_concierge_active
        ) AS is_snooze_concierge_active,
        COALESCE(
            privacy_by_person.is_tenant_message_ai_informative_withdrawn,
            privacy_by_user.is_tenant_message_ai_informative_withdrawn
        ) AS is_tenant_message_ai_informative_withdrawn,
        COALESCE(
            privacy_by_person.is_concierge_privacy_suppressed,
            privacy_by_user.is_concierge_privacy_suppressed
        ) AS is_concierge_privacy_suppressed,
        -- Distinguishes "no purpose expressed" from "identity unresolved".
        (
            privacy_by_person.id_person IS NOT NULL
            OR privacy_by_user.id_user IS NOT NULL
            OR behaviour_person.id_person IS NOT NULL
        ) AS is_privacy_state_known
    FROM
        behaviour_person
    LEFT JOIN
        privacy_facts AS privacy_by_person
        ON behaviour_person.id_person = privacy_by_person.id_person
    LEFT JOIN
        privacy_facts AS privacy_by_user
        ON behaviour_person.id_user = privacy_by_user.id_user
),
facts AS (
    SELECT
        audience_spine.id_user,
        privacy_resolved.id_person,
        tof_facts.id_device,
        -- Cluster cost type is already RENT / SALE; fall back to whichever
        -- context the user searched more in the last 60 days.
        COALESCE(
            hls_facts.cost_type,
            CASE
                WHEN COALESCE(tof_facts.qty_search_sale_60d, 0)
                    > COALESCE(tof_facts.qty_search_rent_60d, 0)
                THEN 'SALE'
                WHEN COALESCE(tof_facts.qty_search_rent_60d, 0) > 0
                THEN 'RENT'
            END
        ) AS business_context,
        hls_facts.cluster_events_count,
        hls_facts.cluster_city,
        hls_facts.cluster_neighborhoods,
        hls_facts.cluster_max_price,
        hls_facts.cluster_bedrooms,
        hls_facts.ts_profile_updated,
        hls_facts.id_user IS NOT NULL
            AND hls_facts.cluster_events_count IS NOT NULL
            AS has_top_cluster,
        COALESCE(hls_facts.cluster_events_count, 0) >= 10
            AS has_qualified_search_cluster,
        COALESCE(hls_facts.qty_low_7d, 0) AS qty_low_7d,
        COALESCE(hls_facts.qty_med_7d, 0) AS qty_med_7d,
        COALESCE(hls_facts.qty_high_7d, 0) AS qty_high_7d,
        COALESCE(hls_facts.qty_low_lifetime, 0) AS qty_low_lifetime,
        COALESCE(hls_facts.qty_med_lifetime, 0) AS qty_med_lifetime,
        COALESCE(hls_facts.qty_high_lifetime, 0) AS qty_high_lifetime,
        hls_facts.ts_last_low,
        hls_facts.ts_last_med,
        hls_facts.ts_last_high,
        hls_facts.last_template_family,
        hls_facts.ts_last_shared_lpv_ads,
        COALESCE(hls_facts.is_whatsapp_blocked, FALSE) AS is_whatsapp_blocked,
        COALESCE(hls_facts.qty_low_lifetime, 0)
            + COALESCE(hls_facts.qty_med_lifetime, 0)
            + COALESCE(hls_facts.qty_high_lifetime, 0) = 0
            AS is_first_notification,
        privacy_resolved.snooze_concierge_status,
        privacy_resolved.tenant_message_ai_informative_status,
        privacy_resolved.ts_snooze_concierge_updated,
        privacy_resolved.ts_tenant_message_ai_informative_updated,
        CASE
            WHEN privacy_resolved.is_privacy_state_known
            THEN COALESCE(privacy_resolved.is_snooze_concierge_active, FALSE)
        END AS is_snooze_concierge_active,
        CASE
            WHEN privacy_resolved.is_privacy_state_known
            THEN COALESCE(
                privacy_resolved.is_tenant_message_ai_informative_withdrawn,
                FALSE
            )
        END AS is_tenant_message_ai_informative_withdrawn,
        CASE
            WHEN privacy_resolved.is_privacy_state_known
            THEN COALESCE(
                privacy_resolved.is_concierge_privacy_suppressed,
                FALSE
            )
        END AS is_concierge_privacy_suppressed,
        COALESCE(visit_facts.qty_visits_tomorrow, 0) AS qty_visits_tomorrow,
        COALESCE(visit_facts.qty_visits_7d, 0) AS qty_visits_7d,
        COALESCE(visit_facts.qty_visits_canceled_1d, 0)
            AS qty_visits_canceled_1d,
        COALESCE(visit_facts.qty_visits_canceled_7d, 0)
            AS qty_visits_canceled_7d,
        COALESCE(visit_facts.qty_visits_rescheduled_1d, 0)
            AS qty_visits_rescheduled_1d,
        COALESCE(visit_facts.qty_visits_rescheduled_7d, 0)
            AS qty_visits_rescheduled_7d,
        visit_facts.id_house_next_visit,
        visit_facts.visit_code_next,
        visit_facts.ts_next_visit,
        visit_facts.id_house_last_canceled_1d,
        visit_facts.visit_code_last_canceled_1d,
        visit_facts.array_id_house_visit_open_or_done,
        COALESCE(offer_facts.has_rent_offer_1d, FALSE) AS has_rent_offer_1d,
        COALESCE(offer_facts.has_rent_offer_7d, FALSE) AS has_rent_offer_7d,
        offer_facts.id_house_last_offer,
        offer_facts.ts_last_offer,
        COALESCE(chat_facts.qty_chat_messages_7d, 0) AS qty_chat_messages_7d,
        COALESCE(chat_facts.qty_chat_messages_28d, 0)
            AS qty_chat_messages_28d,
        chat_facts.ts_last_chat_message,
        COALESCE(tof_facts.qty_search_sessions_7d, 0)
            AS qty_search_sessions_7d,
        COALESCE(tof_facts.qty_search_sessions_60d, 0)
            AS qty_search_sessions_60d,
        COALESCE(tof_facts.qty_search_rent_60d, 0) AS qty_search_rent_60d,
        COALESCE(tof_facts.qty_search_sale_60d, 0) AS qty_search_sale_60d,
        COALESCE(tof_facts.qty_lpv_3d, 0) AS qty_lpv_3d,
        COALESCE(tof_facts.qty_houses_lpv_3d, 0) AS qty_houses_lpv_3d,
        tof_facts.array_id_house_top_5_lpv_3d,
        COALESCE(tof_facts.qty_favorites_1d, 0) AS qty_favorites_1d,
        COALESCE(tof_facts.qty_favorites_7d, 0) AS qty_favorites_7d,
        COALESCE(tof_facts.qty_schedule_page_1d, 0) AS qty_schedule_page_1d,
        tof_facts.id_house_last_lpv,
        tof_facts.id_house_last_favorite,
        tof_facts.id_house_last_schedule,
        tof_facts.dt_last_search,
        tof_facts.ts_last_lpv
    FROM
        audience_spine
    LEFT JOIN
        privacy_resolved
        ON audience_spine.id_user = privacy_resolved.id_user
    LEFT JOIN
        tof_facts
        ON audience_spine.id_user = tof_facts.id_user
    LEFT JOIN
        hls_facts
        ON audience_spine.id_user = hls_facts.id_user
    LEFT JOIN
        visit_facts
        ON audience_spine.id_user = visit_facts.id_user
    LEFT JOIN
        offer_facts
        ON audience_spine.id_user = offer_facts.id_user
    LEFT JOIN
        chat_facts
        ON audience_spine.id_user = chat_facts.id_user
),
-- Medium-intent qualifier, highest priority first, mirroring the tier order
-- the previous audience used.
scored AS (
    SELECT
        facts.*,
        facts.qty_visits_tomorrow = 1 AS meets_high_intent,
        CASE
            WHEN facts.has_rent_offer_1d THEN 'DIRECT_OFFER'
            WHEN facts.qty_schedule_page_1d > 0 THEN 'SCHEDULE_PAGE_VIEWED'
            WHEN facts.qty_favorites_1d > 0 THEN 'FAVORITED_LISTING'
            WHEN facts.qty_lpv_3d >= 3 THEN 'THREE_PLUS_LPV'
        END AS medium_intent_qualifier
    FROM
        facts
)
SELECT
    scored.id_user,
    scored.id_person,
    scored.id_device,
    scored.business_context,
    CASE
        WHEN COALESCE(scored.is_concierge_privacy_suppressed, TRUE)
            THEN 'NOT_CLASSIFIED'
        WHEN scored.is_whatsapp_blocked THEN 'NOT_CLASSIFIED'
        WHEN scored.qty_high_7d > 0 THEN 'NOT_CLASSIFIED'
        WHEN scored.meets_high_intent THEN 'HIGH'
        WHEN scored.qty_med_7d > 0 THEN 'NOT_CLASSIFIED'
        WHEN scored.medium_intent_qualifier IS NOT NULL THEN 'MEDIUM'
        WHEN scored.qty_low_7d > 0 THEN 'NOT_CLASSIFIED'
        WHEN scored.qty_low_lifetime >= 4
            AND scored.qty_chat_messages_28d = 0
            THEN 'NOT_CLASSIFIED'
        WHEN scored.snooze_concierge_status = 'EXPIRED'
            AND scored.qty_search_sessions_60d < 10
            THEN 'NOT_CLASSIFIED'
        WHEN scored.has_top_cluster THEN 'LOW'
        ELSE 'LOW'
    END AS intent,
    CASE
        WHEN scored.is_concierge_privacy_suppressed IS NULL
            THEN 'PRIVACY_STATE_UNKNOWN'
        WHEN scored.is_concierge_privacy_suppressed THEN 'PRIVACY_SUPPRESSED'
        WHEN scored.is_whatsapp_blocked THEN 'WHATSAPP_BLOCKED'
        WHEN scored.qty_high_7d > 0 THEN 'HIGH_INTENT_MSG_RECEIVED'
        WHEN scored.meets_high_intent THEN 'MEETS_CONDITIONS'
        WHEN scored.qty_med_7d > 0 THEN 'MED_INTENT_MSG_RECEIVED'
        WHEN scored.medium_intent_qualifier IS NOT NULL
            THEN 'MEETS_CONDITIONS'
        WHEN scored.qty_low_7d > 0 THEN 'LOW_INTENT_MSG_RECEIVED'
        WHEN scored.qty_low_lifetime >= 4
            AND scored.qty_chat_messages_28d = 0
            THEN 'REPETITION_CONTROL'
        WHEN scored.snooze_concierge_status = 'EXPIRED'
            AND scored.qty_search_sessions_60d < 10
            THEN 'LOW_SEARCHES_AFTER_SNOOZE'
        WHEN scored.has_top_cluster THEN 'MEETS_CONDITIONS'
        ELSE 'CATCH_ALL'
    END AS reason,
    CASE
        WHEN COALESCE(scored.is_concierge_privacy_suppressed, TRUE) THEN NULL
        WHEN scored.is_whatsapp_blocked THEN NULL
        WHEN scored.qty_high_7d > 0 THEN NULL
        WHEN scored.meets_high_intent THEN NULL
        WHEN scored.qty_med_7d > 0 THEN NULL
        ELSE scored.medium_intent_qualifier
    END AS medium_intent_reason,
    CASE
        WHEN scored.meets_high_intent THEN scored.id_house_next_visit
        WHEN scored.medium_intent_qualifier = 'DIRECT_OFFER'
            THEN scored.id_house_last_offer
        WHEN scored.medium_intent_qualifier = 'SCHEDULE_PAGE_VIEWED'
            THEN scored.id_house_last_schedule
        WHEN scored.medium_intent_qualifier = 'FAVORITED_LISTING'
            THEN scored.id_house_last_favorite
        WHEN scored.medium_intent_qualifier = 'THREE_PLUS_LPV'
            THEN scored.id_house_last_lpv
    END AS id_house_target,
    CASE
        WHEN scored.meets_high_intent THEN scored.visit_code_next
    END AS visit_code_target,
    scored.has_top_cluster,
    scored.has_qualified_search_cluster,
    scored.is_first_notification,
    scored.cluster_events_count,
    scored.cluster_city,
    scored.cluster_neighborhoods,
    scored.cluster_max_price,
    scored.cluster_bedrooms,
    scored.ts_profile_updated,
    scored.snooze_concierge_status,
    scored.tenant_message_ai_informative_status,
    scored.ts_snooze_concierge_updated,
    scored.ts_tenant_message_ai_informative_updated,
    scored.is_snooze_concierge_active,
    scored.is_tenant_message_ai_informative_withdrawn,
    scored.is_concierge_privacy_suppressed,
    scored.qty_low_7d,
    scored.qty_med_7d,
    scored.qty_high_7d,
    scored.qty_low_lifetime,
    scored.qty_med_lifetime,
    scored.qty_high_lifetime,
    scored.ts_last_low,
    scored.ts_last_med,
    scored.ts_last_high,
    scored.last_template_family,
    scored.ts_last_shared_lpv_ads,
    scored.is_whatsapp_blocked,
    scored.qty_visits_tomorrow,
    scored.qty_visits_7d,
    scored.qty_visits_canceled_1d,
    scored.qty_visits_canceled_7d,
    scored.qty_visits_rescheduled_1d,
    scored.qty_visits_rescheduled_7d,
    scored.id_house_next_visit,
    scored.visit_code_next,
    scored.ts_next_visit,
    scored.id_house_last_canceled_1d,
    scored.visit_code_last_canceled_1d,
    scored.array_id_house_visit_open_or_done,
    scored.has_rent_offer_1d,
    scored.has_rent_offer_7d,
    scored.id_house_last_offer,
    scored.ts_last_offer,
    scored.qty_chat_messages_7d,
    scored.qty_chat_messages_28d,
    scored.ts_last_chat_message,
    scored.qty_search_sessions_7d,
    scored.qty_search_sessions_60d,
    scored.qty_search_rent_60d,
    scored.qty_search_sale_60d,
    scored.qty_lpv_3d,
    scored.qty_houses_lpv_3d,
    scored.array_id_house_top_5_lpv_3d,
    scored.qty_favorites_1d,
    scored.qty_favorites_7d,
    scored.qty_schedule_page_1d,
    scored.id_house_last_lpv,
    scored.id_house_last_favorite,
    scored.id_house_last_schedule,
    scored.dt_last_search,
    scored.ts_last_lpv,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    scored
