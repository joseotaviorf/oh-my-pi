SELECT
  nudge_id AS id_nudge,
  user_id AS id_user,
  external_nudge_id AS id_external_nudge,
  nudge_type,
  nudge_key,
  status AS nudge_status,
  external_payload,
  snapshot,
  snooze_count AS count_snooze,
  snooze_until AS ts_snooze_until,
  offered_at AS ts_offered,
  activated_at AS ts_activated,
  termination_reason,
  external_updated_at AS ts_external_updated,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_agentic_chatbot_service_raw.nudges
