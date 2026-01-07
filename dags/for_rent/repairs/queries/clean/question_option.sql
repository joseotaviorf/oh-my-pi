SELECT
    id,
    question_id AS id_question,
    next_question_id AS id_next_question,
    diagnosis_id AS id_diagnosis,
    question_option_content_id AS id_question_option_content,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_repairs_raw.question_option
