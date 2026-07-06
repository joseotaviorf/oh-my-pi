WITH incremental_observations AS (
    SELECT
        o.id_observation,
        o.id_trace,
        o.name,
        o.type,
        o.output,
        o.ts_started,
        o.ts_ended,
        o.cost_details
    FROM
        datalake_langfuse_clean.observations AS o
    WHERE
        o.type IN ('AGENT', 'TOOL')
        AND o.name IN (
            'alias_profile_agentV1',
            'alias_inventory_agentV1',
            'alias_get_recommendations_by_company',
            'alias_schedule_visit_agentV1',
            'alias_visit_get_availability',
            'alias_register_visit_intention',
            'alias_escalation_agentV1',
            'alias_get_property_by_external_id',
            'alias_register_escalation'
        )
        AND MAKE_TIMESTAMP(o.year, o.month, o.day, o.hour, 0, 0) >= TIMESTAMP('{load_start_date}')
        AND MAKE_TIMESTAMP(o.year, o.month, o.day, o.hour, 0, 0) < TIMESTAMP('{load_end_date}')
        AND o.ts_started >= TIMESTAMP('{load_start_date}')
        AND o.ts_started < TIMESTAMP('{load_end_date}')
),
affected_session_ids AS (
    SELECT DISTINCT
        t.id_session
    FROM
        datalake_langfuse_clean.traces AS t
    INNER JOIN
        incremental_observations AS io
            ON t.id_trace = io.id_trace
    WHERE
        t.id_session IS NOT NULL
        AND MAKE_TIMESTAMP(t.year, t.month, t.day, t.hour, 0, 0) >= TIMESTAMP('{load_start_date}')
        AND MAKE_TIMESTAMP(t.year, t.month, t.day, t.hour, 0, 0) < TIMESTAMP('{load_end_date}')
),
traces_ordered AS (
    SELECT
        t.id_session AS id_langfuse_session,
        t.id_trace,
        ROW_NUMBER() OVER (PARTITION BY t.id_session ORDER BY t.ts_created) AS turn_number
    FROM
        datalake_langfuse_clean.traces AS t
    INNER JOIN
        datalake_chatbot.sessions AS s
            ON t.id_session = s.id_langfuse_session
    INNER JOIN
        affected_session_ids AS asi
            ON t.id_session = asi.id_session
    WHERE
        s.bot = 'alias'
        AND t.id_session IS NOT NULL
        AND MAKE_TIMESTAMP(t.year, t.month, t.day, t.hour, 0, 0) >= TIMESTAMP('{load_start_date}') - INTERVAL 7 DAY
        AND MAKE_TIMESTAMP(t.year, t.month, t.day, t.hour, 0, 0) < TIMESTAMP('{load_end_date}')
        AND t.ts_created >= DATE('{load_start_date}') - INTERVAL 7 DAY
),
obs_base AS (
    SELECT
        io.id_observation AS sk_agent_call,
        tr.id_langfuse_session,
        io.id_trace,
        lsa.uuid_company,
        io.name AS agent_name,
        io.type AS observation_type,
        io.type = 'TOOL' AS is_tool_call,
        tr.turn_number,
        CAST((UNIX_TIMESTAMP(io.ts_ended) - UNIX_TIMESTAMP(io.ts_started)) * 1000.0 AS DOUBLE) AS duration_ms,
        TRY_CAST(io.cost_details.input AS DOUBLE) AS cost_input_usd,
        TRY_CAST(io.cost_details.output AS DOUBLE) AS cost_output_usd,
        TRY_CAST(io.cost_details.total AS DOUBLE) AS cost_total_usd,
        CAST(NULL AS BIGINT) AS input_tokens,
        CAST(NULL AS BIGINT) AS output_tokens,
        LOWER(COALESCE(io.output, '')) LIKE '%error%' AS had_error,
        CASE
            WHEN LOWER(COALESCE(io.output, '')) LIKE '%error%' THEN io.output
        END AS error_message,
        DATE(s.ts_created) AS dt_session,
        io.ts_started,
        io.ts_ended
    FROM
        incremental_observations AS io
    INNER JOIN
        traces_ordered AS tr
            ON io.id_trace = tr.id_trace
    INNER JOIN
        datalake_chatbot.sessions AS s
            ON tr.id_langfuse_session = s.id_langfuse_session
    LEFT JOIN
        datalake_alias.alias_sessions AS lsa
            ON tr.id_langfuse_session = lsa.id_langfuse_session
)
SELECT
    obs.sk_agent_call,
    obs.id_langfuse_session,
    obs.id_trace,
    COALESCE(cb.sk_broker, -1) AS sk_broker,
    obs.agent_name,
    obs.observation_type,
    obs.is_tool_call,
    obs.turn_number,
    obs.duration_ms,
    obs.cost_input_usd,
    obs.cost_output_usd,
    obs.cost_total_usd,
    obs.input_tokens,
    obs.output_tokens,
    obs.has_error,
    obs.error_message,
    obs.dt_session,
    obs.ts_started,
    obs.ts_ended,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(obs.ts_started) AS year,
    MONTH(obs.ts_started) AS month,
    DAY(obs.ts_started) AS day
FROM
    obs_base AS obs
LEFT JOIN
    core_brokers.brokers AS cb
        ON obs.uuid_company = cb.uuid_company