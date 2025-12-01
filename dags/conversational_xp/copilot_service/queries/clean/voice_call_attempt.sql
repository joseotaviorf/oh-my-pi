SELECT
    id,
    voice_call_external_id AS id_voice_call_external,
    voice_call_provider_id AS id_voice_call_provider,
    voice_session_id AS id_voice_session,
    state,
    created_at AS ts_created,
    scheduled_at AS ts_scheduled
FROM
    datalake_copilot_service_raw.voice_call_attempt
