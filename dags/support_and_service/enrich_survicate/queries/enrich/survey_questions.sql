SELECT
    id_question,
    id_survey,
    type,
    question,
    CASE
        WHEN introduction = '' THEN NULL
        ELSE introduction
    END AS introduction,
    answer_choices IS NOT NULL AS has_answer_choices,
    dt_load,
    year,
    month,
    day
FROM
    datalake_survicate_clean.survey_questions
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}