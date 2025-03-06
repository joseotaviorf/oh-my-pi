SELECT
    id,
    message_id AS id_message,
    content_id AS id_content,
    session_id AS id_session,
    user_id AS id_user,
    taxonomy,
    is_effective,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_chat_fup_test_raw.message_voting