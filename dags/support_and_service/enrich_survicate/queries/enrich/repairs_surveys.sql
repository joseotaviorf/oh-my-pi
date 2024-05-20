SELECT
    rc.id_response AS id_answer,
    sr.id_survey,
    sr.id_respondent,
    PARSE_URL(sr.response_url, 'QUERY', 't_id') AS id_ticket,
    PARSE_URL(sr.response_url, 'QUERY', 'email') AS respondent_email,
    sr.survey_name,
    CASE
        WHEN sr.id_survey = '01176589bb5ad239' THEN "owner"
        WHEN sr.id_survey = 'a514a5d6fe646931' THEN "tenant"
    END AS respondent_type,
    'repairs' AS service_type,
    'offboarding' AS service_context,
    'survicate' AS source_name,
    CAST(COLLECT_LIST(rc.answer_content) FILTER (WHERE rc.id_question IN (1852448, 1852462)) AS STRING) AS improvement_tags,
    LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1852449, 1852463)) AS respondent_comments,
    CAST(LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1852451, 1852461)) AS INT) AS satisfaction_score,
    "satisfaction evaluation" AS score_description,
    CAST(LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1852447, 1852460)) AS INT) AS secondary_satisfaction_score,
    "satisfaction between parties involved" AS secondary_score_description,
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
    sr.id_survey IN ('a514a5d6fe646931', '01176589bb5ad239')
    AND rc.year = {year}
    AND rc.month = {month}
    AND rc.day = {day}
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 14, 16, 17, 18, 19, 20, 21