SELECT
    id,
    survey_id AS id_survey,
    rating,
    comment,
    solved AS is_solved,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_chat_fup_test_raw.surveys_answer
