SELECT
    id,
    user_id AS id_user,
    idempotency_id AS id_idempotency,
    user_phone,
    user_name,
    user_document_number,
    channel,
    call_context,
    state,
    completion_state,
    min_interval_between_calls,
    max_retries,
    initial_date AS ts_started,
    end_date AS ts_ended,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_copilot_service_raw.voice_session
