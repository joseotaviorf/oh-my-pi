SELECT
    chatId AS id_chat,
    vendor.chatId AS id_channel,
    vendor.messageId AS id_message,
    externalUser.id AS id_user_external,
    participantId AS id_participant,
    participantType AS participant_type,
    chatGroup AS chat_group,
    chatType AS chat_type,
    scope,
    index,
    mentions,
    vendor,
    externalUser AS user_external,
    body AS message,
    attributes AS message_attributes,
    CAST(createdAt AS TIMESTAMP) AS ts_created,
    year,
    month,
    day,
    hour
FROM
    datalake_internal_chat_raw.chat5a_messages
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
