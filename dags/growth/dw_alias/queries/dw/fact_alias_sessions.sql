WITH affected_lead_sessions AS (
    SELECT
        uuid_lead_session
    FROM
        datalake_alias_clean.lead_sessions
    WHERE
        ts_updated >= TIMESTAMP('{load_start_date}')
        AND ts_updated < TIMESTAMP('{load_end_date}')
),
affected_langfuse_sessions AS (
    SELECT DISTINCT
        ls.uuid_chat_session AS id_langfuse_session
    FROM
        datalake_alias_clean.lead_sessions AS ls
    INNER JOIN
        affected_lead_sessions AS als
            ON ls.uuid_lead_session = als.uuid_lead_session
    WHERE
        ls.uuid_chat_session IS NOT NULL
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
engagements_agg AS (
    SELECT
        le.uuid_lead_session,
        COUNT(*) AS qt_engagements,
        MIN(le.ts_created) AS ts_engagement_first
    FROM
        datalake_alias_clean.lead_engagements AS le
    INNER JOIN
        affected_lead_sessions AS als
            ON le.uuid_lead_session = als.uuid_lead_session
    GROUP BY
        le.uuid_lead_session
),
first_origin AS (
    SELECT
        uuid_lead_session,
        origin AS origin_first
    FROM (
        SELECT
            le.uuid_lead_session,
            le.origin,
            ROW_NUMBER() OVER (PARTITION BY le.uuid_lead_session ORDER BY le.ts_created) AS rn
        FROM
            datalake_alias_clean.lead_engagements AS le
        INNER JOIN
            affected_lead_sessions AS als
                ON le.uuid_lead_session = als.uuid_lead_session
    )
    WHERE
        rn = 1
),
trace_meta AS (
    SELECT
        t.id_session AS id_langfuse_session,
        COUNT(DISTINCT t.id_trace) AS n_user_turns,
        MAX(t.version) AS bot_version,
        MIN(t.ts_created) AS ts_first_turn,
        MAX(t.ts_created) AS ts_last_turn
    FROM
        datalake_langfuse_clean.traces AS t
    INNER JOIN
        affected_langfuse_sessions AS als
            ON t.id_session = als.id_langfuse_session
    WHERE
        t.id_session IS NOT NULL
    GROUP BY
        t.id_session
),
obt_agg AS (
    SELECT
        t.id_session AS id_langfuse_session,
        MAX(CASE WHEN o.name = 'alias_profile_agentV1' THEN 1 ELSE 0 END) = 1 AS had_profiling,
        MAX(CASE WHEN o.name = 'alias_inventory_agentV1' THEN 1 ELSE 0 END) = 1 AS had_inventory,
        MAX(CASE WHEN o.name = 'alias_get_recommendations_by_company' THEN 1 ELSE 0 END) = 1 AS had_recommendations,
        MAX(CASE WHEN o.name = 'alias_schedule_visit_agentV1' THEN 1 ELSE 0 END) = 1 AS had_scheduling,
        MAX(CASE WHEN o.name = 'alias_visit_get_availability' THEN 1 ELSE 0 END) = 1 AS had_availability,
        MAX(CASE WHEN o.name = 'alias_register_visit_intention' THEN 1 ELSE 0 END) = 1 AS had_visit_registered,
        MAX(CASE WHEN o.name = 'alias_escalation_agentV1' THEN 1 ELSE 0 END) = 1 AS had_escalation,
        MAX(CASE
            WHEN o.name = 'alias_register_visit_intention'
                AND LOWER(o.output) LIKE '%registered successfully%'
            THEN 1 ELSE 0
        END) = 1 AS visit_registered_success,
        MAX(CASE
            WHEN o.name = 'alias_register_escalation'
                AND LOWER(o.output) LIKE '%escalation registered successfully%'
            THEN 1 ELSE 0
        END) = 1 AS escalation_registered_success,
        CASE
            WHEN MAX(CASE WHEN o.name = 'alias_register_visit_intention' THEN 1 ELSE 0 END) = 1
                THEN 'visit_intention_registered'
            WHEN MAX(CASE WHEN o.name = 'alias_escalation_agentV1' THEN 1 ELSE 0 END) = 1
                THEN 'escalated'
            WHEN MAX(CASE WHEN o.name = 'alias_schedule_visit_agentV1' THEN 1 ELSE 0 END) = 1
                THEN 'schedule_visit_agent_called'
            WHEN MAX(CASE WHEN o.name = 'alias_get_recommendations_by_company' THEN 1 ELSE 0 END) = 1
                THEN 'inventory_searched'
            WHEN MAX(CASE WHEN o.name = 'alias_profile_agentV1' THEN 1 ELSE 0 END) = 1
                THEN 'profile_identified'
            ELSE 'no_agent'
        END AS funnel_stage_deepest,
        MIN(CASE WHEN o.name = 'alias_profile_agentV1' THEN o.ts_started END) AS ts_profiling,
        MIN(CASE WHEN o.name = 'alias_inventory_agentV1' THEN o.ts_started END) AS ts_inventory,
        MIN(CASE WHEN o.name = 'alias_schedule_visit_agentV1' THEN o.ts_started END) AS ts_scheduling,
        MIN(CASE WHEN o.name = 'alias_visit_get_availability' THEN o.ts_started END) AS ts_availability,
        MIN(CASE WHEN o.name = 'alias_register_visit_intention' THEN o.ts_started END) AS ts_visit_registered,
        MIN(CASE WHEN o.name = 'alias_escalation_agentV1' THEN o.ts_started END) AS ts_escalation,
        SUM(CASE
            WHEN o.type = 'TOOL' AND LOWER(COALESCE(o.output, '')) LIKE '%error%' THEN 1 ELSE 0
        END) AS n_tool_call_errors,
        SUM(CASE
            WHEN o.name = 'alias_get_recommendations_by_company' AND o.type = 'TOOL' THEN 1 ELSE 0
        END) AS n_calls_get_recommendations,
        SUM(CASE
            WHEN o.name = 'alias_visit_get_availability' AND o.type = 'TOOL' THEN 1 ELSE 0
        END) AS n_calls_get_availability,
        SUM(CASE
            WHEN o.name = 'alias_get_property_by_external_id' AND o.type = 'TOOL' THEN 1 ELSE 0
        END) AS n_calls_get_property,
        SUM(CASE
            WHEN o.name = 'alias_register_visit_intention' AND o.type = 'TOOL' THEN 1 ELSE 0
        END) AS n_calls_register_visit,
        SUM(CASE
            WHEN o.name = 'alias_register_escalation' AND o.type = 'TOOL' THEN 1 ELSE 0
        END) AS n_calls_register_escalation,
        SUM(TRY_CAST(cost_details.total AS DOUBLE)) AS total_llm_cost_usd,
        percentile_approx(
            (UNIX_TIMESTAMP(o.ts_ended) - UNIX_TIMESTAMP(o.ts_started)) * 1000.0, 0.5
        ) AS p50_llm_response_time_ms,
        percentile_approx(
            (UNIX_TIMESTAMP(o.ts_ended) - UNIX_TIMESTAMP(o.ts_started)) * 1000.0, 0.95
        ) AS p95_llm_response_time_ms,
        AVG((UNIX_TIMESTAMP(o.ts_ended) - UNIX_TIMESTAMP(o.ts_started)) * 1000.0) AS avg_llm_response_time_ms
    FROM
        datalake_langfuse_clean.observations AS o
    INNER JOIN
        datalake_langfuse_clean.traces AS t
            ON o.id_trace = t.id_trace
    INNER JOIN
        affected_langfuse_sessions AS als
            ON t.id_session = als.id_langfuse_session
    WHERE
        t.id_session IS NOT NULL
    GROUP BY
        t.id_session
),
broker_config AS (
    SELECT
        t.id_session AS id_langfuse_session,
        COALESCE(
            GET_JSON_OBJECT(o.output, '$.companyUuid'),
            GET_JSON_OBJECT(o.output, '$.companyUUID')
        ) AS company_uuid,
        ROW_NUMBER() OVER (PARTITION BY t.id_session ORDER BY o.ts_started) AS rn
    FROM
        datalake_langfuse_clean.observations AS o
    INNER JOIN
        datalake_langfuse_clean.traces AS t
            ON o.id_trace = t.id_trace
    INNER JOIN
        affected_langfuse_sessions AS als
            ON t.id_session = als.id_langfuse_session
    WHERE
        o.name = 'get_alias_configuration'
        AND o.type = 'TOOL'
        AND t.id_session IS NOT NULL
)
SELECT
    ls.uuid_lead_session AS sk_lead_session,
    ls.uuid_lead AS sk_lead,
    COALESCE(cb.sk_broker, -1) AS sk_broker,
    ls.uuid_chat_session AS id_langfuse_session,
    cs.id_sauron_session,
    ls.status,
    COALESCE(fo.origin_first, 'UNKNOWN') AS origin_first,
    cs.channel,
    ea.ts_engagement_first,
    COALESCE(ea.qt_engagements, 0) AS qt_engagements,
    COALESCE(ra.is_resolved, FALSE) AS is_resolved,
    COALESCE(ra.is_escalated, FALSE) AS is_escalated,
    COALESCE(ra.is_visit_intention, FALSE) AS is_visit_intention,
    COALESCE(ra.is_crm_sent, FALSE) AS is_crm_sent,
    ls.ts_chat_started IS NOT NULL AS is_chat_started,
    COALESCE(ra.qt_resolutions, 0) AS qt_resolutions,
    tm.bot_version,
    COALESCE(bc.company_uuid, '') IN (
        '00000000-0000-4000-8000-000000000001',
        '31616192-288b-439a-baec-890a5c89e20a'
    ) AS is_test,
    COALESCE(oa.had_profiling, FALSE) AS had_profiling,
    COALESCE(oa.had_inventory, FALSE) AS had_inventory,
    COALESCE(oa.had_recommendations, FALSE) AS had_recommendations,
    COALESCE(oa.had_scheduling, FALSE) AS had_scheduling,
    COALESCE(oa.had_availability, FALSE) AS had_availability,
    COALESCE(oa.had_visit_registered, FALSE) AS had_visit_registered,
    COALESCE(oa.had_escalation, FALSE) AS had_escalation,
    COALESCE(oa.visit_registered_success, FALSE) AS visit_registered_success,
    COALESCE(oa.escalation_registered_success, FALSE) AS escalation_registered_success,
    COALESCE(oa.funnel_stage_deepest, 'no_agent') AS funnel_stage_deepest,
    oa.ts_profiling,
    oa.ts_inventory,
    oa.ts_scheduling,
    oa.ts_availability,
    oa.ts_visit_registered,
    oa.ts_escalation,
    COALESCE(tm.n_user_turns, 0) AS n_user_turns,
    NULL AS n_user_turns_until_first_recommendation,
    NULL AS n_user_turns_until_visit_intent,
    COALESCE(oa.n_tool_call_errors, 0) AS n_tool_call_errors,
    COALESCE(oa.n_calls_get_recommendations, 0) AS n_calls_get_recommendations,
    COALESCE(oa.n_calls_get_availability, 0) AS n_calls_get_availability,
    COALESCE(oa.n_calls_get_property, 0) AS n_calls_get_property,
    COALESCE(oa.n_calls_register_visit, 0) AS n_calls_register_visit,
    COALESCE(oa.n_calls_register_escalation, 0) AS n_calls_register_escalation,
    NULL AS n_recommendations_shown,
    oa.total_llm_cost_usd,
    CASE
        WHEN COALESCE(tm.n_user_turns, 0) > 0
            THEN oa.total_llm_cost_usd / tm.n_user_turns
    END AS avg_cost_per_turn_usd,
    NULL AS total_input_tokens,
    NULL AS total_output_tokens,
    oa.avg_llm_response_time_ms,
    oa.p50_llm_response_time_ms,
    oa.p95_llm_response_time_ms,
    NULL AS full_conversation,
    ls.ts_created,
    ls.ts_closed,
    tm.ts_first_turn,
    tm.ts_last_turn,
    CASE
        WHEN tm.ts_first_turn IS NOT NULL AND tm.ts_last_turn IS NOT NULL
            THEN (UNIX_TIMESTAMP(tm.ts_last_turn) - UNIX_TIMESTAMP(tm.ts_first_turn)) / 60.0
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
    engagements_agg AS ea
        ON ls.uuid_lead_session = ea.uuid_lead_session
LEFT JOIN
    first_origin AS fo
        ON ls.uuid_lead_session = fo.uuid_lead_session
LEFT JOIN
    resolutions_agg AS ra
        ON ls.uuid_lead_session = ra.uuid_lead_session
LEFT JOIN
    trace_meta AS tm
        ON ls.uuid_chat_session = tm.id_langfuse_session
LEFT JOIN
    obt_agg AS oa
        ON ls.uuid_chat_session = oa.id_langfuse_session
LEFT JOIN
    broker_config AS bc
        ON ls.uuid_chat_session = bc.id_langfuse_session
        AND bc.rn = 1
