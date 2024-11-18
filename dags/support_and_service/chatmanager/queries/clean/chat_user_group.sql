SELECT
    chat_group_id AS id_chat_group,
    chat_user_id AS id_chat_user,
    state,
    visible,
    profile,
    last_read_index,
    attributes,
    last_read_at AS ts_last_read,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_chatmanager_raw.chatusergroup
