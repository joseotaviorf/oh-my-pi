SELECT
    rc.id_response AS id_answer,
    sr.id_survey,
    sr.id_respondent,
    LAST(rc.answer_content) FILTER (WHERE rc.id_question = 1639216) AS respondent_type,
    sr.survey_name,
    'keys' AS service_type,
    'lockbox' AS service_context,
    'survicate' AS source_name,
    CAST(COLLECT_LIST(rc.answer_content) FILTER (WHERE rc.id_question = 1514144) AS STRING) AS improvement_tags,
    LAST(rc.answer_content) FILTER (WHERE rc.id_question = 1514145) AS respondent_comments,
    CAST(LAST(rc.answer_content) FILTER (WHERE rc.id_question = 1514143) AS INT) AS satisfaction_score,
    "satisfaction evaluation" AS score_description,
    rc.ts_collected AS ts_submitted,
    rc.dt_load,
    rc.year,
    rc.month,
    rc.day
FROM
    datalake_survicate.response_content AS rc
JOIN
    datalake_survicate.survey_responses AS sr
        ON sr.id_response = rc.id_response
WHERE
    sr.id_survey = 'efe52808bddcd15f'
    AND rc.year = {year}
    AND rc.month = {month}
    AND rc.day = {day}
GROUP BY 1, 2, 3, 5, 6, 7, 8, 12, 13, 14, 15, 16, 17