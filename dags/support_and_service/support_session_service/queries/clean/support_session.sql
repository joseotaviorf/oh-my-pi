SELECT
    id,
    status,
    agent,
    user_data,
    user_phone,
    context,
    created_by,
    source,
    source_env,
    source_identity,
    department,
    tags,
    ticket_comments,
    metadata,
    created_at AS ts_created,
    updated_at AS ts_updated,
    last_message_at AS ts_last_message,
    first_message_at AS ts_first_message,
    year,
    month,
    day
FROM
    datalake_support_session_service_raw.support_session
