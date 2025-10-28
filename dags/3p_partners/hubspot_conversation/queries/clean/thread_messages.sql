SELECT
    id AS id_thread_message,
    conversationsThreadId AS id_thread_conversation,
    channelId AS id_channel,
    channelAccountId AS id_channel_account,
    createdBy AS created_by,
    text,
    richText AS rich_text,
    status,
    truncationStatus AS truncation_status,
    type,
    direction,
    attachments,
    client,
    senders,
    recipients,
    CAST(archived AS BOOLEAN) AS is_archived,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    CAST(updatedAt AS TIMESTAMP) AS ts_updated,
    ts_load,
    year,
    month,
    day,
    hour
FROM
    datalake_hubspot_raw.thread_messages
WHERE
    ts_load BETWEEN '{load_start_date}' AND '{load_end_date}'