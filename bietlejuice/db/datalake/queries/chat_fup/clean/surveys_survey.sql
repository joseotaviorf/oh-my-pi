SELECT
    id,
    token,
    pending as is_pending,
    timestamp(created_at) as ts_created,
    timestamp(updated_at) as ts_updated,
    chat_id as id_chat
FROM datalake_chat_fup_raw.surveys_survey