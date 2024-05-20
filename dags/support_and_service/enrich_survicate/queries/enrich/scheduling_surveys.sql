SELECT
    rc.id_response AS id_answer,
    sr.id_survey,
    sr.id_respondent,
    PARSE_URL(sr.response_url, 'QUERY', 'contractid') AS id_contract,
    sr.survey_name,
    CASE
      WHEN sr.id_survey = 'b1133bc4925426d0' THEN 'owner'
      WHEN sr.id_survey = '278f21b367c2344c' THEN 'tenant'
    END AS respondent_type,
    'RSS' AS service_type,
    CASE
      WHEN sr.id_survey = 'b1133bc4925426d0' THEN 'onboarding'
      WHEN sr.id_survey = '278f21b367c2344c' THEN 'offboarding'
    END AS service_context,
    'survicate' AS source_name,
    CAST(COLLECT_LIST(rc.answer_content) FILTER (WHERE rc.id_question IN (1259234, 1602020)) AS STRING) AS improvement_tags,
    LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1259256, 1602021)) AS respondent_comments,
    CAST(LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1259203, 1602019)) AS INT) AS satisfaction_score,
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
    sr.id_survey IN ('b1133bc4925426d0', '278f21b367c2344c')
    AND rc.year = {year}
    AND rc.month = {month}
    AND rc.day = {day}
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 13, 14, 15, 16, 17, 18
