SELECT
    id,
    job_id AS id_job,
    question_id AS id_question,
    candidate_id AS id_candidate,
    job_title,
    question,
    "type",
    answer,
    candidate_name,
    answer_created_at AS ts_answer_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_workable_redshift_raw.answers
WHERE 
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')