SELECT
    id,
    chat_id AS id_chat,
    token,
    pending AS is_pending,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_chat_fup_test_raw.surveys_survey
