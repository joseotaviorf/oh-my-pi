WITH traces_ordered AS (
    SELECT
        t.id_session AS id_langfuse_session,
        t.id_trace,
        ROW_NUMBER() OVER (PARTITION BY t.id_session ORDER BY t.ts_created) AS turn_number
    FROM
        datalake_langfuse_clean.traces AS t
    INNER JOIN
        datalake_chatbot.sessions AS s
            ON t.id_session = s.id_langfuse_session
    WHERE
        s.bot = 'alias'
        AND t.id_session IS NOT NULL
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
    WHERE
        o.name = 'get_alias_configuration'
        AND o.type = 'TOOL'
        AND t.id_session IS NOT NULL
),
obs_base AS (
    SELECT
        o.id_observation AS sk_agent_call,
        tr.id_langfuse_session,
        o.id_trace,
        bc.company_uuid,
        o.name AS agent_name,
        o.type AS observation_type,
        o.type = 'TOOL' AS is_tool_call,
        tr.turn_number,
        CAST((UNIX_TIMESTAMP(o.ts_ended) - UNIX_TIMESTAMP(o.ts_started)) * 1000.0 AS DOUBLE) AS duration_ms,
        TRY_CAST(cost_details.input AS DOUBLE) AS cost_input_usd,
        TRY_CAST(cost_details.output AS DOUBLE) AS cost_output_usd,
        TRY_CAST(cost_details.total AS DOUBLE) AS cost_total_usd,
        NULL AS input_tokens,
        NULL AS output_tokens,
        LOWER(COALESCE(o.output, '')) LIKE '%error%' AS had_error,
        CASE
            WHEN LOWER(COALESCE(o.output, '')) LIKE '%error%' THEN o.output
        END AS error_message,
        DATE(s.ts_created) AS dt_session,
        o.ts_started,
        o.ts_ended
    FROM
        datalake_langfuse_clean.observations AS o
    INNER JOIN
        traces_ordered AS tr
            ON o.id_trace = tr.id_trace
    INNER JOIN
        datalake_chatbot.sessions AS s
            ON tr.id_langfuse_session = s.id_langfuse_session
    LEFT JOIN
        broker_config AS bc
            ON tr.id_langfuse_session = bc.id_langfuse_session
            AND bc.rn = 1
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
    obs.had_error,
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
        ON obs.company_uuid = cb.uuid_company