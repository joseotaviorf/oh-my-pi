SELECT
    id,
    solved as is_solved,
    rating,
    comment,
    timestamp(created_at) as ts_created,
    timestamp(updated_at) as ts_updated,
    survey_id as id_survey
FROM datalake_chat_fup_raw.surveys_answer