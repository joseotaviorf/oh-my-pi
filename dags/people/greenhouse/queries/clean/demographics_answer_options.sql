SELECT
    id,
    demographic_question_id AS id_demographic_question,
    free_form,
    CAST(active AS BOOLEAN) AS is_active,
    translations,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.demographics_answer_options