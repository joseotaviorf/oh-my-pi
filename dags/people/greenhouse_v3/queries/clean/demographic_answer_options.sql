SELECT
    -- ids
    id AS id_demographic_answer_option,
    demographic_question_id AS id_demographic_question,
    -- text fields
    name,
    'en' AS language,
    -- boolean
    CAST(free_form AS BOOLEAN) AS is_free_form,
    CAST(active AS BOOLEAN) AS is_active,
    -- timestamps
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.demographic_answer_options
