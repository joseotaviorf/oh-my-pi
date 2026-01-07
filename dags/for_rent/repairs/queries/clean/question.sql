SELECT
    id,
    question_content_id AS id_question_content,
    subgroup_id AS id_subgroup,
    type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_repairs_raw.question
