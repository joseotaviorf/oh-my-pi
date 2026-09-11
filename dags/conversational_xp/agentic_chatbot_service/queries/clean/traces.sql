-- Clean projection for datalake_agentic_chatbot_service_clean.traces.
-- Source: datalake_agentic_chatbot_service_raw.traces (Debezium CDC of agentic-chatbot-service.public.traces).
-- The `payload` column holds the full, versioned hades TraceEvent as JSON
-- (envelope + conversation content + nested agent-execution tree).
--
-- Parsing is keyed on TraceEvent.version and FAILS LOUD on any unknown/unsupported
-- version: an unexpected version aborts the run via raise_error (CNVPL-2085 AC).
-- DELETE handling (purge) is done by the framework via `has_soft_delete: true` in the
-- declaration, so no op filtering is needed here.
SELECT
  event_id,
  GET_JSON_OBJECT(payload, '$.chatbot_id') AS id_chatbot,
  GET_JSON_OBJECT(payload, '$.trace_id')   AS id_trace,
  session_id                               AS id_session,
  GET_JSON_OBJECT(payload, '$.user_id')    AS id_user,
  -- Fail-loud version guard. Bump the supported set deliberately when the contract changes.
  CASE
    WHEN CAST(GET_JSON_OBJECT(payload, '$.version') AS INT) = 1
      THEN CAST(GET_JSON_OBJECT(payload, '$.version') AS INT)
    ELSE RAISE_ERROR(
      CONCAT(
        'Unknown TraceEvent version ',
        COALESCE(GET_JSON_OBJECT(payload, '$.version'), '<null>'),
        ' for event_id ',
        event_id
      )
    )
  END AS version,
  GET_JSON_OBJECT(payload, '$.name')       AS event_name,
  generated_at AS ts_generated,
  received_at  AS ts_received,
  -- Full invocation data (input/output + agent-execution tree) kept as JSON for downstream navigation.
  GET_JSON_OBJECT(payload, '$.data')       AS data_json,
  -- Distinct agents that took part in the invocation (feeds session enrichment / CNVPL-2042).
  ARRAY_DISTINCT(
    TRANSFORM(
      FROM_JSON(
        GET_JSON_OBJECT(payload, '$.data.traces'),
        'array<struct<agent_name: string>>'
      ),
      t -> t.agent_name
    )
  ) AS agents_called
FROM
  datalake_agentic_chatbot_service_raw.traces
