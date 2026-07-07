WITH traces_in_window AS (
    SELECT
        t.id_trace,
        t.id_session AS id_langfuse_session,
        t.ts_created,
        t.version
    FROM
        datalake_langfuse_clean.traces AS t
    INNER JOIN
        datalake_chatbot.sessions AS s
            ON t.id_session = s.id_langfuse_session
            AND s.bot = 'alias'
    WHERE
        t.id_session IS NOT NULL
        AND MAKE_TIMESTAMP(t.year, t.month, t.day, t.hour, 0, 0) >= TIMESTAMP('{load_start_date}') - INTERVAL 1 DAY
        AND MAKE_TIMESTAMP(t.year, t.month, t.day, t.hour, 0, 0) < TIMESTAMP('{load_end_date}')
        AND t.ts_created >= DATE('{load_start_date}') - INTERVAL 1 DAY
        AND t.ts_created < TIMESTAMP('{load_end_date}')
),
observations_in_window AS (
    SELECT
        o.id_trace,
        o.name AS obs_name,
        o.type AS obs_type,
        o.output AS obs_output,
        o.ts_started,
        o.ts_ended,
        o.cost_details
    FROM
        datalake_langfuse_clean.observations AS o
    WHERE
        o.type IN ('GENERATION', 'AGENT', 'TOOL')
        AND MAKE_TIMESTAMP(o.year, o.month, o.day, o.hour, 0, 0) >= TIMESTAMP('{load_start_date}') - INTERVAL 1 DAY
        AND MAKE_TIMESTAMP(o.year, o.month, o.day, o.hour, 0, 0) < TIMESTAMP('{load_end_date}')
),
traces_with_obs AS (
    SELECT
        tw.id_trace,
        tw.id_langfuse_session,
        tw.ts_created AS trace_ts_created,
        tw.version AS trace_version,
        o.obs_name,
        o.obs_type,
        o.obs_output,
        o.ts_started,
        o.ts_ended,
        o.cost_details
    FROM
        traces_in_window AS tw
    LEFT JOIN
        observations_in_window AS o
            ON tw.id_trace = o.id_trace
)
SELECT
    tw.id_langfuse_session,
    MIN_BY(
        COALESCE(
            GET_JSON_OBJECT(tw.obs_output, '$.companyUuid'),
            GET_JSON_OBJECT(tw.obs_output, '$.companyUUID')
        ),
        tw.ts_started
    ) FILTER (WHERE tw.obs_name = 'get_alias_configuration' AND tw.obs_type = 'TOOL') AS uuid_company,
    MAX(tw.trace_version) AS bot_version,
    CASE
        WHEN MAX(CASE
            WHEN tw.obs_name = 'alias_register_visit_intention'
                AND LOWER(tw.obs_output) LIKE '%registered successfully%'
            THEN 1 ELSE 0
        END) = 1
            THEN 'visit_intention_registered'
        WHEN MAX(CASE WHEN tw.obs_name = 'alias_escalation_agentV1' THEN 1 ELSE 0 END) = 1
            THEN 'escalated'
        WHEN MAX(CASE WHEN tw.obs_name = 'alias_register_visit_intention' THEN 1 ELSE 0 END) = 1
            THEN 'visit_attempt_failed'
        WHEN MAX(CASE WHEN tw.obs_name = 'alias_schedule_visit_agentV1' THEN 1 ELSE 0 END) = 1
            THEN 'schedule_visit_agent_called'
        WHEN MAX(CASE WHEN tw.obs_name = 'alias_get_recommendations_by_company' THEN 1 ELSE 0 END) = 1
            THEN 'inventory_searched'
        WHEN MAX(CASE WHEN tw.obs_name = 'alias_profile_agentV1' THEN 1 ELSE 0 END) = 1
            THEN 'profile_identified'
        ELSE 'no_agent'
    END AS funnel_stage_deepest,
    COUNT(DISTINCT tw.id_trace) AS n_user_turns,
    SUM(CASE
        WHEN tw.obs_type = 'TOOL'
            AND LOWER(COALESCE(tw.obs_output, '')) LIKE '%error%'
        THEN 1 ELSE 0
    END) AS n_tool_call_errors,
    SUM(CASE
        WHEN tw.obs_name = 'alias_get_recommendations_by_company'
            AND tw.obs_type = 'TOOL'
        THEN 1 ELSE 0
    END) AS n_calls_get_recommendations,
    SUM(CASE
        WHEN tw.obs_name = 'alias_visit_get_availability'
            AND tw.obs_type = 'TOOL'
        THEN 1 ELSE 0
    END) AS n_calls_get_availability,
    SUM(CASE
        WHEN tw.obs_name = 'alias_get_property_by_external_id'
            AND tw.obs_type = 'TOOL'
        THEN 1 ELSE 0
    END) AS n_calls_get_property,
    SUM(CASE
        WHEN tw.obs_name = 'alias_register_visit_intention'
            AND tw.obs_type = 'TOOL'
        THEN 1 ELSE 0
    END) AS n_calls_register_visit,
    SUM(CASE
        WHEN tw.obs_name = 'alias_register_escalation'
            AND tw.obs_type = 'TOOL'
        THEN 1 ELSE 0
    END) AS n_calls_register_escalation,
    SUM(TRY_CAST(tw.cost_details.total AS DOUBLE)) AS total_llm_cost_usd,
    percentile_approx(
        (UNIX_TIMESTAMP(tw.ts_ended) - UNIX_TIMESTAMP(tw.ts_started)) * 1000.0,
        0.5
    ) AS p50_llm_response_time_ms,
    percentile_approx(
        (UNIX_TIMESTAMP(tw.ts_ended) - UNIX_TIMESTAMP(tw.ts_started)) * 1000.0,
        0.95
    ) AS p95_llm_response_time_ms,
    AVG(
        (UNIX_TIMESTAMP(tw.ts_ended) - UNIX_TIMESTAMP(tw.ts_started)) * 1000.0
    ) AS avg_llm_response_time_ms,
    MAX(CASE WHEN tw.obs_name = 'alias_profile_agentV1' THEN 1 ELSE 0 END) = 1 AS has_profiling,
    MAX(CASE WHEN tw.obs_name = 'alias_inventory_agentV1' THEN 1 ELSE 0 END) = 1 AS has_inventory,
    MAX(CASE WHEN tw.obs_name = 'alias_get_recommendations_by_company' THEN 1 ELSE 0 END) = 1 AS has_recommendations,
    MAX(CASE
        WHEN tw.obs_name = 'alias_get_recommendations_by_company'
            AND tw.obs_type = 'TOOL'
            AND (
                GET_JSON_OBJECT(tw.obs_output, '$.listings[0]') IS NOT NULL
                OR GET_JSON_OBJECT(tw.obs_output, '$.hlsresult.listings[0]') IS NOT NULL
            )
        THEN 1 ELSE 0
    END) = 1 AS has_actual_recommendations,
    MAX(CASE WHEN tw.obs_name = 'alias_schedule_visit_agentV1' THEN 1 ELSE 0 END) = 1 AS has_scheduling,
    MAX(CASE WHEN tw.obs_name = 'alias_visit_get_availability' THEN 1 ELSE 0 END) = 1 AS has_availability,
    MAX(CASE WHEN tw.obs_name = 'alias_register_visit_intention' THEN 1 ELSE 0 END) = 1 AS has_visit_registered,
    MAX(CASE WHEN tw.obs_name = 'alias_escalation_agentV1' THEN 1 ELSE 0 END) = 1 AS has_escalation,
    MAX(CASE
        WHEN tw.obs_name = 'alias_register_visit_intention'
            AND LOWER(tw.obs_output) LIKE '%registered successfully%'
        THEN 1 ELSE 0
    END) = 1 AS visit_registered_success,
    MAX(CASE
        WHEN tw.obs_name = 'alias_register_escalation'
            AND LOWER(tw.obs_output) LIKE '%escalation registered successfully%'
        THEN 1 ELSE 0
    END) = 1 AS escalation_registered_success,
    MIN(tw.trace_ts_created) AS ts_first_turn,
    MAX(tw.trace_ts_created) AS ts_last_turn,
    MIN(CASE WHEN tw.obs_name = 'alias_profile_agentV1' THEN tw.ts_started END) AS ts_profiling,
    MIN(CASE WHEN tw.obs_name = 'alias_inventory_agentV1' THEN tw.ts_started END) AS ts_inventory,
    MIN(CASE WHEN tw.obs_name = 'alias_schedule_visit_agentV1' THEN tw.ts_started END) AS ts_scheduling,
    MIN(CASE WHEN tw.obs_name = 'alias_visit_get_availability' THEN tw.ts_started END) AS ts_availability,
    MIN(CASE WHEN tw.obs_name = 'alias_register_visit_intention' THEN tw.ts_started END) AS ts_visit_registered,
    MIN(CASE WHEN tw.obs_name = 'alias_escalation_agentV1' THEN tw.ts_started END) AS ts_escalation,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(MIN(tw.trace_ts_created)) AS year,
    MONTH(MIN(tw.trace_ts_created)) AS month,
    DAY(MIN(tw.trace_ts_created)) AS day
FROM
    traces_with_obs AS tw
GROUP BY
    tw.id_langfuse_session
