SELECT
    id,
    question_id AS id_question,
    question_option_id AS id_question_option,
    repair_request_item_id AS id_repair_request_item,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_repairs_raw.form_answer

