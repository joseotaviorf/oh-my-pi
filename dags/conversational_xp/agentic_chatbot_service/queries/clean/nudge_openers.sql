SELECT
  user_id AS id_user,
  nudge_id AS id_nudge,
  text AS opener_text,
  metadata AS opener_metadata,
  generated_at AS ts_generated
FROM
  datalake_agentic_chatbot_service_raw.nudge_openers
