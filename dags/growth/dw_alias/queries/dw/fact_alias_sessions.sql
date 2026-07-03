WITH affected_lead_sessions AS (
    SELECT
        uuid_lead_session
    FROM
        datalake_alias_clean.lead_sessions
    WHERE
        ts_updated >= TIMESTAMP('{load_start_date}')
        AND ts_updated < TIMESTAMP('{load_end_date}')
),
resolutions_agg AS (
    SELECT
        lr.uuid_lead_session,
        COUNT(*) AS qt_resolutions,
        TRUE AS is_resolved,
        MAX(CASE WHEN lr.type = 'ESCALATION' THEN TRUE ELSE FALSE END) AS is_escalated,
        MAX(CASE WHEN lr.type = 'VISIT_INTENTION' THEN TRUE ELSE FALSE END) AS is_visit_intention,
        MAX(CASE WHEN lr.ts_sent_to_crm IS NOT NULL THEN TRUE ELSE FALSE END) AS is_crm_sent
    FROM
        datalake_alias_clean.lead_resolutions AS lr
    INNER JOIN
        affected_lead_sessions AS als
            ON lr.uuid_lead_session = als.uuid_lead_session
    GROUP BY
        lr.uuid_lead_session
),
engagements_base AS (
    SELECT
        le.uuid_lead_session,
        COUNT(*) AS qt_engagements,
        MIN(le.ts_created) AS ts_engagement_first,
        MIN(CASE
            WHEN le.rn = 1 THEN le.origin
        END) AS origin_first
    FROM (
        SELECT
            le.uuid_lead_session,
            le.origin,
            le.ts_created,
            ROW_NUMBER() OVER (PARTITION BY le.uuid_lead_session ORDER BY le.ts_created) AS rn
        FROM
            datalake_alias_clean.lead_engagements AS le
        INNER JOIN
            affected_lead_sessions AS als
                ON le.uuid_lead_session = als.uuid_lead_session
    ) AS le
    GROUP BY
        le.uuid_lead_session
)
SELECT
    ls.uuid_lead_session AS sk_lead_session,
    ls.uuid_lead AS sk_lead,
    COALESCE(cb.sk_broker, -1) AS sk_broker,
    ls.uuid_chat_session AS id_langfuse_session,
    cs.id_sauron_session,
    ls.status,
    COALESCE(eb.origin_first, 'UNKNOWN') AS origin_first,
    cs.channel,
    eb.ts_engagement_first,
    COALESCE(eb.qt_engagements, 0) AS qt_engagements,
    COALESCE(ra.is_resolved, FALSE) AS is_resolved,
    COALESCE(ra.is_escalated, FALSE) AS is_escalated,
    COALESCE(ra.is_visit_intention, FALSE) AS is_visit_intention,
    COALESCE(ra.is_crm_sent, FALSE) AS is_crm_sent,
    ls.ts_chat_started IS NOT NULL AS is_chat_started,
    COALESCE(ra.qt_resolutions, 0) AS qt_resolutions,
    lsa.bot_version,
    COALESCE(lsa.uuid_company, '') IN (
        '00000000-0000-4000-8000-000000000001',
        '31616192-288b-439a-baec-890a5c89e20a'
    ) AS is_test,
    COALESCE(lsa.has_profiling, FALSE) AS has_profiling,
    COALESCE(lsa.has_inventory, FALSE) AS has_inventory,
    COALESCE(lsa.has_recommendations, FALSE) AS has_recommendations,
    COALESCE(lsa.has_scheduling, FALSE) AS has_scheduling,
    COALESCE(lsa.has_availability, FALSE) AS has_availability,
    COALESCE(lsa.has_visit_registered, FALSE) AS has_visit_registered,
    COALESCE(lsa.has_escalation, FALSE) AS has_escalation,
    COALESCE(lsa.visit_registered_success, FALSE) AS visit_registered_success,
    COALESCE(lsa.escalation_registered_success, FALSE) AS escalation_registered_success,
    COALESCE(lsa.funnel_stage_deepest, 'no_agent') AS funnel_stage_deepest,
    lsa.ts_profiling,
    lsa.ts_inventory,
    lsa.ts_scheduling,
    lsa.ts_availability,
    lsa.ts_visit_registered,
    lsa.ts_escalation,
    COALESCE(lsa.n_user_turns, 0) AS n_user_turns,
    NULL AS n_user_turns_until_first_recommendation,
    NULL AS n_user_turns_until_visit_intent,
    COALESCE(lsa.n_tool_call_errors, 0) AS n_tool_call_errors,
    COALESCE(lsa.n_calls_get_recommendations, 0) AS n_calls_get_recommendations,
    COALESCE(lsa.n_calls_get_availability, 0) AS n_calls_get_availability,
    COALESCE(lsa.n_calls_get_property, 0) AS n_calls_get_property,
    COALESCE(lsa.n_calls_register_visit, 0) AS n_calls_register_visit,
    COALESCE(lsa.n_calls_register_escalation, 0) AS n_calls_register_escalation,
    NULL AS n_recommendations_shown,
    lsa.total_llm_cost_usd,
    CASE
        WHEN COALESCE(lsa.n_user_turns, 0) > 0
            THEN lsa.total_llm_cost_usd / lsa.n_user_turns
    END AS avg_cost_per_turn_usd,
    NULL AS total_input_tokens,
    NULL AS total_output_tokens,
    lsa.avg_llm_response_time_ms,
    lsa.p50_llm_response_time_ms,
    lsa.p95_llm_response_time_ms,
    NULL AS full_conversation,
    ls.ts_created,
    ls.ts_closed,
    lsa.ts_first_turn,
    lsa.ts_last_turn,
    CASE
        WHEN lsa.ts_first_turn IS NOT NULL AND lsa.ts_last_turn IS NOT NULL
            THEN (UNIX_TIMESTAMP(lsa.ts_last_turn) - UNIX_TIMESTAMP(lsa.ts_first_turn)) / 60.0
    END AS session_wall_duration_min,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(ls.ts_created) AS year,
    MONTH(ls.ts_created) AS month,
    DAY(ls.ts_created) AS day
FROM
    datalake_alias_clean.lead_sessions AS ls
INNER JOIN
    affected_lead_sessions AS als
        ON ls.uuid_lead_session = als.uuid_lead_session
LEFT JOIN
    datalake_alias_clean.leads AS l
        ON ls.uuid_lead = l.uuid_lead
LEFT JOIN
    core_brokers.brokers AS cb
        ON l.uuid_company = cb.uuid_company
LEFT JOIN
    datalake_chatbot.sessions AS cs
        ON ls.uuid_chat_session = cs.id_langfuse_session
LEFT JOIN
    engagements_base AS eb
        ON ls.uuid_lead_session = eb.uuid_lead_session
LEFT JOIN
    resolutions_agg AS ra
        ON ls.uuid_lead_session = ra.uuid_lead_session
LEFT JOIN
    datalake_alias.alias_sessions AS lsa
        ON ls.uuid_chat_session = lsa.id_langfuse_session