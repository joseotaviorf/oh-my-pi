SELECT
    -- ids
    id AS id_approver,
    -- Non-ids (foreign keys)
    user_id AS id_user,
    approver_group_id AS id_approver_group,
    resolved_by_id AS id_resolved_by,
    reminder_sent_by_id AS id_reminder_sent_by,
    added_by_custom_field_id AS id_added_by_custom_field,
    -- Non-metrics (properties)
    status,
    sort_order,
    version_sent,
    reminders_sent,
    auto_reminders_sent,
    send_auto_reminder_at,
    -- Date, timestamp
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    CAST(resolved_at AS TIMESTAMP) AS ts_resolved,
    CAST(request_sent_at AS TIMESTAMP) AS ts_request_sent,
    CAST(reminder_sent_at AS TIMESTAMP) AS ts_reminder_sent,
    NOW() AS ts_load,
    -- Partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.approvers

