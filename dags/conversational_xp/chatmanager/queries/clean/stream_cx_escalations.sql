SELECT
    id,
    stream_id AS id_stream,
    support_session_id AS id_support_session,
    escalation_data,
    status,
    created_at AS ts_created,
    ready_at AS ts_ready,
    ended_at AS ts_ended,
    failed_at AS ts_failed,
    updated_at AS ts_updated
FROM
    datalake_chatmanager_raw.stream_cx_escalations
