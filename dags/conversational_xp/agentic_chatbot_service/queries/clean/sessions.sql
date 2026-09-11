-- Clean projection for datalake_agentic_chatbot_service_clean.sessions.
-- Source: datalake_agentic_chatbot_service_raw.agentic_sessions (Debezium CDC of
-- agentic-chatbot-service.public.agentic_sessions).
--
-- Grain: one row per (stream_id, session_id). The same stream_id can have many
-- historical sessions over time; closed_at IS NULL means the session is open.
-- Close / TTL activity arrive as CDC UPDATEs (no hard DELETEs from the app).
SELECT
  stream_id AS id_stream,
  session_id AS id_session,
  created_at AS ts_created,
  updated_at AS ts_updated,
  closed_at AS ts_closed,
  closed_at IS NULL AS is_open
FROM
  datalake_agentic_chatbot_service_raw.agentic_sessions
