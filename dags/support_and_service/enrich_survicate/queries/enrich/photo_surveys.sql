SELECT
    rc.id_response,
    sr.id_survey,
    sr.id_respondent,
    PARSE_URL(sr.response_url, 'QUERY', 'sk_owner') AS id_owner,
    sr.survey_name,
    'OWNER' AS respondent_type,
    'photos' AS service_type,
    'listing' AS service_context,
    'survicate' AS survey_source,
    CAST(COLLECT_LIST(rc.answer_content) FILTER (WHERE rc.id_question = 1269662) AS STRING) AS improvement_tags,
    LAST(rc.answer_content) FILTER (WHERE rc.id_question = 1269663) AS respondent_comments,
    CAST(LAST(rc.answer_content) FILTER (WHERE rc.id_question = 1269661) AS INT) AS satisfaction_rating,
    "satisfaction evaluation" AS score_description,
    rc.ts_collected AS ts_first_response,
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
    sr.id_survey = '46a1af7804f7a9ac'
    AND rc.year = {year}
    AND rc.month = {month}
    AND rc.day = {day}
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 12, 13, 14, 15, 16, 17
