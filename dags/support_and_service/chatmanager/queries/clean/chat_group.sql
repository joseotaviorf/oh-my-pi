SELECT
    id
    last_chat_vendor_id AS id_last_chat_vendor,
    chat_subtype_id AS id_chat_subtype,
    uuid,
    version,
    type,
    chat_group,
    state,
    last_message_sent_by,
    last_message_type,
    last_message_body,
    last_message_index,
    last_message_data,
    attributes,
    last_message_media_content_type,
    last_chat_vendor_name,
    chat_subtype,
    created_at AS ts_created,
    last_message_sent_at AS ts_last_message_sent,
    updated_at AS ts_updated
FROM
    datalake_chatmanager_raw.chatgroup
