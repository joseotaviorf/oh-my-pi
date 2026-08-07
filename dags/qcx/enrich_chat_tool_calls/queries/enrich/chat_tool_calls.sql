-- ================================================================
-- Consórcio chat tool calls façade
-- Grain: one row per Langfuse TOOL observation (id_tool_call)
-- Scoped to Conrado (Langfuse tag); join to chat_* via id_session
-- Incremental merge on id_tool_call over {load_start_date}..{load_end_date}
-- (scheduled default: last 30 days; override conf for historical backfill)
-- ================================================================
WITH conrado_traces AS (
  SELECT
    langfuse_traces.id_trace,
    langfuse_traces.id_session AS id_langfuse_session,
    LOWER(langfuse_traces.tags[0]) AS host_name,
    -- Blip conversation id (uuid@tunnel.msging.net), not contact
    langfuse_traces.id_user AS id_bsp
  FROM
    datalake_langfuse_clean.traces AS langfuse_traces
  WHERE
    langfuse_traces.ts_created >= DATE('{load_start_date}')
    AND langfuse_traces.ts_created < DATE_ADD(DATE('{load_end_date}'), 1)
    AND langfuse_traces.id_session IS NOT NULL
    AND langfuse_traces.tags IS NOT NULL
    AND SIZE(langfuse_traces.tags) > 0
    AND langfuse_traces.tags[0] IS NOT NULL
    AND LOWER(langfuse_traces.tags[0]) = 'conrado'
),
tool_observations AS (
  SELECT
    langfuse_observations.id_observation AS id_tool_call,
    langfuse_observations.id_trace,
    langfuse_observations.name AS tool_name,
    CAST(langfuse_observations.input AS STRING) AS tool_args,
    CAST(langfuse_observations.output AS STRING) AS tool_output,
    langfuse_observations.level AS observation_level,
    -- Langfuse latency is stored in seconds; expose milliseconds for fast tools
    TRY_CAST(langfuse_observations.latency AS DOUBLE) * 1000.0 AS latency_milliseconds,
    langfuse_observations.ts_started,
    langfuse_observations.ts_ended,
    -- Langfuse has no first-class exit_code; best-effort from common output keys
    COALESCE(
      TRY_CAST(GET_JSON_OBJECT(CAST(langfuse_observations.output AS STRING), '$.exit_code') AS INT),
      TRY_CAST(GET_JSON_OBJECT(CAST(langfuse_observations.output AS STRING), '$.status_code') AS INT),
      TRY_CAST(GET_JSON_OBJECT(CAST(langfuse_observations.output AS STRING), '$.http_status') AS INT)
    ) AS exit_code
  FROM
    datalake_langfuse_clean.observations AS langfuse_observations
  INNER JOIN
    conrado_traces
      ON conrado_traces.id_trace = langfuse_observations.id_trace
  WHERE
    langfuse_observations.type = 'TOOL'
    AND langfuse_observations.ts_started >= DATE('{load_start_date}')
    AND langfuse_observations.ts_started < DATE_ADD(DATE('{load_end_date}'), 1)
),
-- Copilot session ↔ Langfuse session (same bridge as enrich_chat_messages).
-- Empirically 1:1 (id_external → one Copilot session); no dedupe needed.
session_bridge AS (
  SELECT DISTINCT
    copilot_session.id AS id_session,
    copilot_session.id_external AS id_langfuse_session
  FROM
    datalake_copilot_service_clean.session AS copilot_session
  INNER JOIN
    conrado_traces
      ON conrado_traces.id_langfuse_session = copilot_session.id_external
  WHERE
    copilot_session.id_external IS NOT NULL
),
-- Langfuse traces.id_user matches lead_external_data.id_bsp_conversation (~91% hit)
lead_by_bsp AS (
  SELECT
    CASE
      WHEN INSTR(lead_external.id_bsp_conversation, '@') > 0
        THEN lead_external.id_bsp_conversation
      ELSE CONCAT(lead_external.id_bsp_conversation, '@tunnel.msging.net')
    END AS id_bsp,
    lead_external.id_lead,
    lead_external.id_crm,
    ROW_NUMBER() OVER (
      PARTITION BY
        CASE
          WHEN INSTR(lead_external.id_bsp_conversation, '@') > 0
            THEN lead_external.id_bsp_conversation
          ELSE CONCAT(lead_external.id_bsp_conversation, '@tunnel.msging.net')
        END
      ORDER BY
        lead_external.ts_updated DESC NULLS LAST,
        lead_external.ts_created DESC
    ) AS rn
  FROM
    datalake_consorcio_clean.lead_external_data AS lead_external
  WHERE
    lead_external.id_bsp_conversation IS NOT NULL
)
SELECT
  tool_observations.id_tool_call,
  session_bridge.id_session,
  tool_observations.id_trace,
  lead_bridge.id_lead,
  conrado_traces.id_bsp,
  lead_bridge.id_crm,
  CAST(consorcio_lead.uuid AS STRING) AS uuid_lead,
  conrado_traces.host_name,
  tool_observations.tool_name,
  tool_observations.tool_args,
  tool_observations.tool_output,
  tool_observations.observation_level,
  tool_observations.exit_code,
  COALESCE(
    tool_observations.latency_milliseconds,
    CASE
      WHEN tool_observations.ts_started IS NOT NULL
        AND tool_observations.ts_ended IS NOT NULL
        THEN (
          UNIX_MILLIS(tool_observations.ts_ended)
          - UNIX_MILLIS(tool_observations.ts_started)
        )
    END
  ) AS latency_milliseconds,
  tool_observations.ts_started,
  tool_observations.ts_ended,
  YEAR(tool_observations.ts_started) AS year,
  MONTH(tool_observations.ts_started) AS month,
  DAY(tool_observations.ts_started) AS day
FROM
  tool_observations
INNER JOIN
  conrado_traces
    ON conrado_traces.id_trace = tool_observations.id_trace
INNER JOIN
  session_bridge
    ON session_bridge.id_langfuse_session = conrado_traces.id_langfuse_session
LEFT JOIN
  lead_by_bsp AS lead_bridge
    ON lead_bridge.id_bsp = conrado_traces.id_bsp
   AND lead_bridge.rn = 1
LEFT JOIN
  datalake_consorcio_clean.lead AS consorcio_lead
    ON consorcio_lead.id = lead_bridge.id_lead
WHERE
  tool_observations.id_tool_call IS NOT NULL
  AND tool_observations.ts_started IS NOT NULL
