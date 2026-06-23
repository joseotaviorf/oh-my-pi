SELECT
    uuid AS uuid_lead_session,
    lead_uuid AS uuid_lead,
    expiration_reminder_id AS uuid_expiration_reminder,
    chat_session_id AS uuid_chat_session,
    status,
    summary,
    CAST(closed_at AS TIMESTAMP) AS ts_closed,
    CAST(chat_started_at AS TIMESTAMP) AS ts_chat_started,
    CAST(last_message_received_at AS TIMESTAMP) AS ts_last_message_received,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    YEAR(CAST(updated_at AS TIMESTAMP)) AS year,
    MONTH(CAST(updated_at AS TIMESTAMP)) AS month,
    DAY(CAST(updated_at AS TIMESTAMP)) AS day
FROM
    datalake_alias_raw.lead_sessions