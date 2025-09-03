SELECT
    -- ids
    id,
    application_id AS id_application,
    demographic_question_id AS id_demographic_question,
    demographic_answer_option_id AS id_demographic_answer_option,
    -- text fields
    free_form_text,
    -- timestamps
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.demographics_answers
WHERE
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')