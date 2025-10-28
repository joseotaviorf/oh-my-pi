SELECT
    id AS id_thread,
    inboxId AS id_inbox,
    originalChannelId AS id_original_channel,	
    originalChannelAccountId AS id_original_channel_account,	
    associatedContactId AS id_associated_contact,
    status,	
    assignedTo AS assigned_to,
    CAST(spam AS BOOLEAN) AS is_spam,
    CAST(archived AS BOOLEAN) AS is_archived,
    CAST(latestMessageTimestamp AS TIMESTAMP) AS ts_latest_message_timestamp,
    CAST(latestMessageSentTimestamp AS TIMESTAMP) AS ts_latest_message_sent_timestamp,
    CAST(latestMessageReceivedTimestamp AS TIMESTAMP) AS ts_latest_message_received_timestamp,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    ts_load,
    year,
    month,
    day,
    hour
FROM
    datalake_hubspot_raw.threads
WHERE
    ts_load BETWEEN '{load_start_date}' AND '{load_end_date}'