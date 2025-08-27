SELECT
    -- ids
    id,
    demographic_question_set_id AS id_demographic_question_set,
    -- text fields
    name,
    answer_type,
    -- boolean
    CAST(active AS BOOLEAN) AS is_active,
    CAST(required AS BOOLEAN) AS is_required,
    -- timestamps
    NOW() AS ts_load,
    -- arrays
    translations,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.demographics_questions