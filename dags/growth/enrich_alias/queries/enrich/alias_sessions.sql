-- Grain: one row per id_langfuse_session (Alias bot only).
-- Scope: INNER JOIN datalake_chatbot.sessions (bot = 'alias') — same filter as
-- dw_alias.fact_alias_agent_calls; avoids scanning all Langfuse sessions in the window.
-- Partition pruning anchor: traces.ts_created — lookback de 1 dia cobre sessões que cruzam a meia-noite.
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
        AND t.ts_created >= DATE('{load_start_date}') - INTERVAL 1 DAY
        AND t.ts_created < TIMESTAMP('{load_end_date}')
),
traces_with_obs AS (
    SELECT
        tw.id_trace,
        tw.id_langfuse_session,
        tw.ts_created AS trace_ts_created,
        tw.version AS trace_version,
        o.name AS obs_name,
        o.type AS obs_type,
        o.output AS obs_output,
        o.ts_started,
        o.ts_ended,
        o.cost_details
    FROM
        traces_in_window AS tw
    LEFT JOIN
        datalake_langfuse_clean.observations AS o
            ON tw.id_trace = o.id_trace
),
config_per_session AS (
    SELECT
        id_langfuse_session,
        COALESCE(
            GET_JSON_OBJECT(obs_output, '$.companyUuid'),
            GET_JSON_OBJECT(obs_output, '$.companyUUID')
        ) AS uuid_company,
        ROW_NUMBER() OVER (PARTITION BY id_langfuse_session ORDER BY ts_started) AS rn
    FROM
        traces_with_obs
    WHERE
        obs_name = 'get_alias_configuration'
        AND obs_type = 'TOOL'
),
session_agg_base AS (
    SELECT
        tw.id_langfuse_session,
        COUNT(DISTINCT tw.id_trace) AS n_user_turns,
        MAX(tw.trace_version) AS bot_version,
        MIN(tw.trace_ts_created) AS ts_first_turn,
        MAX(tw.trace_ts_created) AS ts_last_turn,
        MAX(CASE WHEN tw.obs_name = 'alias_profile_agentV1' THEN 1 ELSE 0 END) = 1 AS has_profiling,
        MAX(CASE WHEN tw.obs_name = 'alias_inventory_agentV1' THEN 1 ELSE 0 END) = 1 AS has_inventory,
        MAX(CASE WHEN tw.obs_name = 'alias_get_recommendations_by_company' THEN 1 ELSE 0 END) = 1 AS has_recommendations,
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
        CASE
            WHEN MAX(CASE WHEN tw.obs_name = 'alias_register_visit_intention' THEN 1 ELSE 0 END) = 1
                THEN 'visit_intention_registered'
            WHEN MAX(CASE WHEN tw.obs_name = 'alias_escalation_agentV1' THEN 1 ELSE 0 END) = 1
                THEN 'escalated'
            WHEN MAX(CASE WHEN tw.obs_name = 'alias_schedule_visit_agentV1' THEN 1 ELSE 0 END) = 1
                THEN 'schedule_visit_agent_called'
            WHEN MAX(CASE WHEN tw.obs_name = 'alias_get_recommendations_by_company' THEN 1 ELSE 0 END) = 1
                THEN 'inventory_searched'
            WHEN MAX(CASE WHEN tw.obs_name = 'alias_profile_agentV1' THEN 1 ELSE 0 END) = 1
                THEN 'profile_identified'
            ELSE 'no_agent'
        END AS funnel_stage_deepest,
        MIN(CASE WHEN tw.obs_name = 'alias_profile_agentV1' THEN tw.ts_started END) AS ts_profiling,
        MIN(CASE WHEN tw.obs_name = 'alias_inventory_agentV1' THEN tw.ts_started END) AS ts_inventory,
        MIN(CASE WHEN tw.obs_name = 'alias_schedule_visit_agentV1' THEN tw.ts_started END) AS ts_scheduling,
        MIN(CASE WHEN tw.obs_name = 'alias_visit_get_availability' THEN tw.ts_started END) AS ts_availability,
        MIN(CASE WHEN tw.obs_name = 'alias_register_visit_intention' THEN tw.ts_started END) AS ts_visit_registered,
        MIN(CASE WHEN tw.obs_name = 'alias_escalation_agentV1' THEN tw.ts_started END) AS ts_escalation,
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
        ) AS avg_llm_response_time_ms
    FROM
        traces_with_obs AS tw
    GROUP BY
        tw.id_langfuse_session
)
SELECT
    sa.id_langfuse_session,
    cf.uuid_company,
    sa.bot_version,
    sa.funnel_stage_deepest,
    sa.n_user_turns,
    sa.n_tool_call_errors,
    sa.n_calls_get_recommendations,
    sa.n_calls_get_availability,
    sa.n_calls_get_property,
    sa.n_calls_register_visit,
    sa.n_calls_register_escalation,
    sa.total_llm_cost_usd,
    sa.p50_llm_response_time_ms,
    sa.p95_llm_response_time_ms,
    sa.avg_llm_response_time_ms,
    sa.has_profiling,
    sa.has_inventory,
    sa.has_recommendations,
    sa.has_scheduling,
    sa.has_availability,
    sa.has_visit_registered,
    sa.has_escalation,
    sa.visit_registered_success,
    sa.escalation_registered_success,
    sa.ts_first_turn,
    sa.ts_last_turn,
    sa.ts_profiling,
    sa.ts_inventory,
    sa.ts_scheduling,
    sa.ts_availability,
    sa.ts_visit_registered,
    sa.ts_escalation,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(sa.ts_first_turn) AS year,
    MONTH(sa.ts_first_turn) AS month,
    DAY(sa.ts_first_turn) AS day
FROM
    session_agg_base AS sa
LEFT JOIN
    config_per_session AS cf
        ON sa.id_langfuse_session = cf.id_langfuse_session
        AND cf.rn = 1