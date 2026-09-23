-- One row per chatbot session (isaias + wall-e with tracked events) with the supply lead handled during it.
-- 7-day rolling window: [load_start_date, load_end_date] inclusive (DAG params: ds-6 .. ds) merged on id_langfuse_session.
-- Session-to-lead attribution only; no conversion outcome.
WITH base_sessions AS (
    -- Target sessions (small) -> broadcastable everywhere downstream
    SELECT
        s.id_langfuse_session,
        s.id_sss_session,
        CAST(s.id_sauron_session AS STRING) AS id_sauron_session,
        CAST(s.ts_created AS TIMESTAMP) AS ts_session_start,
        s.host_tag,
        s.user_phone_number AS phone_number,
        s.bot
    FROM
        datalake_chatbot.sessions AS s
    WHERE
        s.bot IN ('isaias', 'wall-e')
        AND s.ts_created >= DATE('{load_start_date}')
        AND s.ts_created < DATE_ADD(DATE('{load_end_date}'), 1)
),
session_message_anchors AS (
    -- Message-level anchor timestamps. Broadcast the small session set into messages.
    SELECT /*+ BROADCAST(bs) */
        bs.phone_number,
        bs.id_langfuse_session,
        COALESCE(m.ts_created, bs.ts_session_start) AS anchor_time
    FROM
        base_sessions AS bs
    LEFT JOIN
        datalake_chatbot.messages AS m
            ON COALESCE(bs.id_sauron_session, CAST(bs.id_sss_session AS STRING))
                = COALESCE(CAST(m.id_sauron_session AS STRING), CAST(m.id_sss_session AS STRING))
            AND m.conversation_type = 'HUMAN-AI'
            AND m.ts_created >= DATE('{load_start_date}')
            AND m.ts_created < DATE_ADD(DATE('{load_end_date}'), 1)
),
cdp_events AS (
    -- Relevant CDP transactional events for the supply draft/publish/photo funnel
    SELECT
        from_json(user_properties, 'MAP<STRING,STRING>')['egw_whatsapp.verifiedPhoneNumber'] AS phone_number,
        ts_event AS event_time,
        CAST(GET_JSON_OBJECT(event_properties, '$.lead_id') AS BIGINT) AS retrieved_lead_id,
        event_name
    FROM
        datalake_cdp_clean.transactional
    WHERE
        event_name IN (
            'supply_user_context_not_found', 'supply_draft_succeeded',
            'supply_draft_operation_failed', 'supply_photo_times_fetched',
            'supply_photo_times_fetch_failed', 'supply_draft_fetched',
            'supply_draft_fetch_failed', 'supply_price_suggestion_fetched',
            'supply_price_suggestion_failed', 'supply_lead_published',
            'supply_lead_publish_failed', 'supply_photo_session_scheduled',
            'supply_photo_session_schedule_failed', 'supply_draft_updated',
            'supply_draft_update_failed', 'supply_coverage_validated',
            'supply_listing_type_validated', 'supply_listing_type_validation_failed',
            'supply_property_type_validated', 'supply_property_type_validation_failed',
            'supply_vacancy_validated', 'supply_vacancy_validation_failed',
            'supply_value_in_range_validated', 'supply_value_in_range_validation_failed',
            'supply_photo_session_rescheduled', 'supply_photo_session_reschedule_failed',
            'supply_list_user_photo_sessions_success', 'supply_list_user_photo_sessions_failed',
            'supply_get_available_photo_schedule_success', 'supply_get_available_photo_schedule_failed',
            'supply_get_photo_session_success', 'supply_get_photo_session_failed'
        )
        AND ts_event >= DATE('{load_start_date}')
        AND ts_event < DATE_ADD(DATE('{load_end_date}'), 1)
),
combined_timeline AS (
    -- Interleave message anchors + events into one timeline per phone number
    SELECT
        phone_number,
        anchor_time AS event_time,
        id_langfuse_session,
        CAST(NULL AS BIGINT) AS retrieved_lead_id,
        CAST(NULL AS STRING) AS event_name,
        1 AS event_order
    FROM
        session_message_anchors
    WHERE
        phone_number IS NOT NULL
    UNION ALL
    SELECT
        phone_number,
        event_time,
        CAST(NULL AS STRING) AS id_langfuse_session,
        retrieved_lead_id,
        event_name,
        2 AS event_order
    FROM
        cdp_events
    WHERE
        phone_number IS NOT NULL
),
timeline_with_assigned_sessions AS (
    -- Forward-fill langfuse session id from most recent message onto later events
    SELECT
        phone_number,
        event_time,
        retrieved_lead_id,
        event_name,
        event_order,
        LAST_VALUE(id_langfuse_session) IGNORE NULLS OVER (
            PARTITION BY phone_number
            ORDER BY event_time ASC, event_order ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS assigned_langfuse_session
    FROM
        combined_timeline
),
session_event_agg AS (
    -- One aggregation per session: tracked-event flag, reschedule flag, and last event lead id
    SELECT
        assigned_langfuse_session AS id_langfuse_session,
        TRUE AS has_tracked_events,
        BOOL_OR(
            event_name IN (
                'supply_photo_session_rescheduled', 'supply_photo_session_reschedule_failed',
                'supply_list_user_photo_sessions_success', 'supply_list_user_photo_sessions_failed',
                'supply_get_available_photo_schedule_success', 'supply_get_available_photo_schedule_failed',
                'supply_get_photo_session_success', 'supply_get_photo_session_failed'
            )
        ) AS has_reschedule_event,
        -- strictly last non-null lead by (event_time, event_order) DESC; null-lead rows are ignored
        MAX_BY(
            retrieved_lead_id,
            IF(retrieved_lead_id IS NOT NULL, STRUCT(event_time, event_order), NULL)
        ) AS event_lead_id
    FROM
        timeline_with_assigned_sessions
    WHERE
        event_order = 2
        AND assigned_langfuse_session IS NOT NULL
    GROUP BY
        1
),
inbound_leads AS (
    -- Inbound attribution leads per session, semi-joined to the target sessions only
    SELECT
        id_session,
        COLLECT_SET(id_lead_ebdb) AS array_inbound_leads,
        MAX(id_lead_ebdb) AS fallback_inbound_lead_id
    FROM
        datalake_supply_flows.inbound_attribution
    WHERE
        id_session IN (SELECT id_sauron_session FROM base_sessions)
    GROUP BY
        1
),
staging_session_spine AS (
    -- 1:1 session spine with resolved lead key precomputed once
    SELECT /*+ BROADCAST(sea, il) */
        bs.id_langfuse_session,
        bs.id_sss_session,
        bs.id_sauron_session,
        bs.ts_session_start,
        bs.bot,
        sea.event_lead_id,
        il.array_inbound_leads,
        il.fallback_inbound_lead_id,
        COALESCE(sea.has_tracked_events, FALSE) AS has_tracked_events,
        COALESCE(sea.has_reschedule_event, FALSE) AS has_reschedule_event,
        COALESCE(sea.event_lead_id, il.fallback_inbound_lead_id) AS resolved_lead_key
    FROM
        base_sessions AS bs
    LEFT JOIN
        session_event_agg AS sea
            ON bs.id_langfuse_session = sea.id_langfuse_session
    LEFT JOIN
        inbound_leads AS il
            ON bs.id_sauron_session = il.id_session
),
candidate_leads AS (
    -- Only the lead ids the final join can possibly match; prunes the lookup below
    SELECT DISTINCT
        resolved_lead_key AS id_lead
    FROM
        staging_session_spine
    WHERE
        resolved_lead_key IS NOT NULL
),
lead_origin_pruned AS (
    -- Lead creation times, pruned to candidate leads and the load window
    SELECT
        id_lead_ebdb,
        ts_event
    FROM
        datalake_supply_flows.lead_origin
    WHERE
        ts_event >= DATE('{load_start_date}')
        AND ts_event < DATE_ADD(DATE('{load_end_date}'), 1)
        AND id_lead_ebdb IN (SELECT id_lead FROM candidate_leads)
)
SELECT
    spine.id_langfuse_session,
    spine.id_sss_session,
    spine.id_sauron_session,
    -- guardrail: nullify lead if retrieved before creation (via lead_origin)
    CASE
        WHEN ARRAY_CONTAINS(spine.array_inbound_leads, spine.event_lead_id) THEN spine.resolved_lead_key
        WHEN spine.event_lead_id IS NULL AND spine.fallback_inbound_lead_id IS NOT NULL THEN spine.fallback_inbound_lead_id
        WHEN lo.ts_event IS NOT NULL AND spine.ts_session_start < lo.ts_event THEN CAST(NULL AS STRING)
        ELSE spine.resolved_lead_key
    END AS resolved_lead_id,
    spine.bot,
    -- guardrail: acquisition type
    CASE
        WHEN spine.resolved_lead_key IS NULL THEN 'no_lead'
        WHEN spine.event_lead_id IS NULL AND spine.fallback_inbound_lead_id IS NOT NULL THEN 'created_in_session'
        WHEN ARRAY_CONTAINS(spine.array_inbound_leads, spine.event_lead_id) THEN 'created_in_session'
        WHEN lo.ts_event IS NOT NULL AND spine.ts_session_start < lo.ts_event THEN 'no_lead'
        ELSE 'retrieved_lead'
    END AS lead_acquisition_type,
    spine.has_reschedule_event,
    spine.ts_session_start
FROM
    staging_session_spine AS spine
LEFT JOIN
    lead_origin_pruned AS lo
        ON spine.resolved_lead_key = lo.id_lead_ebdb
WHERE
    spine.bot = 'isaias'
    OR (spine.bot = 'wall-e' AND spine.has_tracked_events = TRUE)
