SELECT
    sq.id_question,
    sq.id_survey,
    sq.type,
    sq.question,
    s.survey_name,
    CASE
        WHEN sq.introduction = '' THEN NULL
        ELSE sq.introduction
    END AS introduction,
    sq.answer_choices IS NOT NULL AS has_answer_choices,
    sq.dt_load,
    sq.year,
    sq.month,
    sq.day
FROM
    datalake_survicate_clean.survey_questions AS sq
LEFT JOIN
    datalake_survicate_clean.surveys AS s
        ON sq.id_survey = s.id_survey
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}