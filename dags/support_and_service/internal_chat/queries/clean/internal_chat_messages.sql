SELECT
    chatId AS id_chat,
    participantId AS id_participant,
    chatGroup AS chat_group,
    externalUser AS user_external,
    index,
    mentions,
    vendor,
    scope,
    body AS message,
    attributes AS message_attributes,
    participantType AS participant_type,
    chatType AS chat_type,
    createdAt AS ts_created,
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
