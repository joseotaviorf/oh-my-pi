SELECT
    -- ids
    id AS id_demographic_question,
    demographic_question_set_id AS id_demographic_question_set,
    -- text fields
    name,
    answer_type,
    'en' AS language,
    -- boolean
    CAST(active AS BOOLEAN) AS is_active,
    CAST(required AS BOOLEAN) AS is_required,
    -- timestamps
    NOW() AS ts_load,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.demographic_questions
