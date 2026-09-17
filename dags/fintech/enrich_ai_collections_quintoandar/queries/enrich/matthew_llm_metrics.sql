-- Matthew/Wall-e prod observations in the incremental window, restricted to the names/types
-- the metrics below consume. Sessions last at most one day, so a 1-day lookback captures each
-- full session (including one that straddles midnight).
WITH obs AS (
    SELECT
        trc.id_session AS id_langfuse_session,
        obs.id_trace,
        obs.id_observation,
        obs.id_parent_observation,
        LOWER(obs.name) AS name_l,
        obs.type,
        obs.level,
        obs.provided_model_name,
        obs.cost_details.total AS cost_total,
        obs.latency,
        obs.ts_started,
        COALESCE(obs.ts_ended, obs.ts_started) AS ts_ref
    FROM
        datalake_langfuse_clean.observations AS obs
    INNER JOIN
        datalake_langfuse_clean.traces AS trc
            ON trc.id_trace = obs.id_trace
    INNER JOIN
        datalake_chatbot.sessions AS cs
            ON cs.id_langfuse_session = trc.id_session
            AND cs.bot IN ('matthew', 'wall-e')
    WHERE
        obs.ts_started >= TIMESTAMP('{load_start_date}') - INTERVAL 2 DAY
        AND trc.environment = 'prod'
        AND trc.id_session IS NOT NULL
        AND (
            obs.type = 'GENERATION'
            OR LOWER(obs.name) = '/v3/messages'
            OR LOWER(obs.name) = 'collectionsinput'
            OR LOWER(obs.name) RLIKE '^collectionsagentv[0-9]+input$'
            OR LOWER(obs.name) RLIKE '^collectionsagentv[0-9]+ - reactplanner$'
            OR LOWER(obs.name) = 'host - hostplanner'
        )
),
-- One row per collections-agent LLM call: the model, cost and latency come from the
-- GENERATION child of each CollectionsAgentV<N> - ReactPlanner observation. The collections
-- agent is the only place Matthew calls an LLM, so this is "the Matthew model".
llm_calls AS (
    SELECT
        p.id_langfuse_session,
        p.id_trace,
        g.provided_model_name AS matthew_model,
        g.cost_total AS llm_call_cost,
        g.latency AS llm_call_latency
    FROM
        obs AS p
    INNER JOIN
        obs AS g
            ON g.id_parent_observation = p.id_observation
    WHERE
        p.name_l RLIKE '^collectionsagentv[0-9]+ - reactplanner$'
        AND p.type = 'AGENT'
        AND g.type = 'GENERATION'
),
-- Collections-agent-input observation per trace: its latency is the total time spent
-- inside the collections agent for that message; level = 'ERROR' marks a timeout.
-- MAX() dedupes the nested (outer + inner) twin rows emitted per trace.
collections_input AS (
    SELECT
        id_langfuse_session,
        id_trace,
        MAX(latency) AS collections_agent_latency,
        MAX(CASE WHEN level = 'ERROR' THEN 1 ELSE 0 END) AS flag_trace_timeout
    FROM
        obs
    WHERE
        name_l = 'collectionsinput'
        OR name_l RLIKE '^collectionsagentv[0-9]+input$'
    GROUP BY
        id_langfuse_session, id_trace
),
-- Total LLM cost per trace = every GENERATION cost (moderator + agent + answer processor);
-- MAX(latency) over the trace equals the /v3/messages root span = total message latency.
trace_cost AS (
    SELECT
        id_langfuse_session,
        id_trace,
        SUM(cost_total) AS total_llm_cost,
        MAX(latency) AS total_message_latency
    FROM
        obs
    WHERE
        type = 'GENERATION'
        OR name_l = '/v3/messages'
    GROUP BY
        id_langfuse_session, id_trace
),
llm_by_trace AS (
    SELECT
        id_langfuse_session,
        id_trace,
        COUNT(*) AS n_llm_calls,
        SUM(llm_call_cost) AS collections_agent_cost,
        SUM(llm_call_latency) AS collections_agent_llm_latency
    FROM
        llm_calls
    GROUP BY
        id_langfuse_session, id_trace
),
-- Driving set: one row per trace (= message) in scope, carrying the reference timestamp.
trace_ts AS (
    SELECT
        id_langfuse_session,
        id_trace,
        MAX(ts_ref) AS ts_ref
    FROM
        obs
    GROUP BY
        id_langfuse_session, id_trace
),
per_trace AS (
    SELECT
        tt.id_langfuse_session,
        tt.id_trace,
        tt.ts_ref,
        COALESCE(lt.n_llm_calls, 0) AS n_llm_calls,
        COALESCE(lt.collections_agent_cost, 0) AS collections_agent_cost,
        COALESCE(lt.collections_agent_llm_latency, 0) AS collections_agent_llm_latency,
        ci.collections_agent_latency,
        COALESCE(ci.flag_trace_timeout, 0) AS flag_trace_timeout,
        COALESCE(tc.total_llm_cost, 0) AS total_llm_cost,
        tc.total_message_latency,
        CASE WHEN COALESCE(lt.n_llm_calls, 0) > 0 THEN 1 ELSE 0 END AS flag_agent_message
    FROM
        trace_ts AS tt
    LEFT JOIN
        llm_by_trace AS lt
            ON lt.id_langfuse_session = tt.id_langfuse_session AND lt.id_trace = tt.id_trace
    LEFT JOIN
        collections_input AS ci
            ON ci.id_langfuse_session = tt.id_langfuse_session AND ci.id_trace = tt.id_trace
    LEFT JOIN
        trace_cost AS tc
            ON tc.id_langfuse_session = tt.id_langfuse_session AND tc.id_trace = tt.id_trace
),
-- Exactly one model per session (asserted); take the first deterministically.
session_model AS (
    SELECT
        id_langfuse_session,
        MIN(matthew_model) AS matthew_model
    FROM
        llm_calls
    WHERE
        matthew_model IS NOT NULL
    GROUP BY
        id_langfuse_session
),
-- Matthew WhatsApp host planner: first Host - HostPlanner GENERATION (ChatOpenAI or
-- NormalizedChatOpenAI child) defines the host LLM version for the session.
host_planner_calls AS (
    SELECT
        p.id_langfuse_session,
        g.provided_model_name AS matthew_host_model,
        p.ts_started AS ts_host_planner_started
    FROM
        obs AS p
    INNER JOIN
        obs AS g
            ON g.id_parent_observation = p.id_observation
    WHERE
        p.name_l = 'host - hostplanner'
        AND g.type = 'GENERATION'
        AND g.name_l IN ('chatopenai', 'normalizedchatopenai')
        AND g.provided_model_name IS NOT NULL
),
host_planner_first_ranked AS (
    SELECT
        id_langfuse_session,
        matthew_host_model,
        ROW_NUMBER() OVER (
            PARTITION BY id_langfuse_session
            ORDER BY ts_host_planner_started ASC
        ) AS rn
    FROM
        host_planner_calls
),
session_host AS (
    SELECT
        id_langfuse_session,
        matthew_host_model,
        CASE
            WHEN matthew_host_model = 'openai/gpt-4o-2024-11-20' THEN 'V1'
            WHEN matthew_host_model = 'openai/gpt-5.6-luna' THEN 'V2'
            ELSE NULL
        END AS matthew_host_version
    FROM
        host_planner_first_ranked
    WHERE
        rn = 1
)
SELECT
    t.id_langfuse_session,
    MIN(sm.matthew_model) AS matthew_model,
    MIN(sh.matthew_host_model) AS matthew_host_model,
    MIN(sh.matthew_host_version) AS matthew_host_version,
    SUM(t.flag_agent_message) AS n_agent_messages,
    SUM(t.n_llm_calls) AS n_llm_calls,
    -- COST (USD)
    SUM(t.total_llm_cost) AS total_llm_cost,
    SUM(t.collections_agent_cost) AS total_collections_agent_cost,
    -- LATENCY (seconds), agent-message-scoped for the *_per_message numerators
    SUM(CASE WHEN t.flag_agent_message = 1 THEN t.total_message_latency END) AS total_message_latency_sum,
    SUM(CASE WHEN t.flag_agent_message = 1 THEN t.collections_agent_latency END) AS collections_agent_latency_sum,
    SUM(t.collections_agent_llm_latency) AS collections_agent_llm_latency_sum,
    MAX(t.flag_trace_timeout) AS flag_session_had_timeout,
    MAX(t.ts_ref) AS ts_ref,
    YEAR(MAX(t.ts_ref)) AS year,
    MONTH(MAX(t.ts_ref)) AS month,
    DAYOFMONTH(MAX(t.ts_ref)) AS day
FROM
    per_trace AS t
LEFT JOIN
    session_model AS sm
        ON sm.id_langfuse_session = t.id_langfuse_session
LEFT JOIN
    session_host AS sh
        ON sh.id_langfuse_session = t.id_langfuse_session
GROUP BY
    t.id_langfuse_session
