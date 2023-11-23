SELECT
    rc.id_response AS id_answer,
    sr.id_survey,
    PARSE_URL(sr.response_url, 'QUERY', 'contractid') AS id_contract,
    PARSE_URL(sr.response_url, 'QUERY', 'inspectionId') AS id_inspection,
    c.id_user AS id_respondent,
    sr.id_respondent AS respondent_uuid,
    CASE
        WHEN sr.id_survey = '00f46ff66c2ff389' THEN 'owner'
        WHEN sr.id_survey = '9d64bf0e2f6faa48' THEN 'tenat'
    END AS respondent_type,
    'inspections' AS service_type,
    'offboarding' AS service_context,
    'survicate' AS source_name,
    CAST(COLLECT_LIST(rc.answer_content) FILTER (WHERE rc.id_question IN (1869883, 1926516)) AS STRING) AS improvement_tags,
    LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1869884, 1926532)) AS respondent_comments,
    LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1835806, 1926509)) AS satisfaction_score,
    "satisfaction evaluation" AS score_description,
    LAST(rc.answer_content) FILTER (WHERE rc.id_question = 1835786) AS secondary_satisfaction_score,
    "house satisfaction" AS secondary_score_description,
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
LEFT JOIN
    datalake_ebdb_clean.contract AS c
        ON c.id = PARSE_URL(sr.response_url, 'QUERY', 'contractid')
WHERE
    sr.id_survey IN ('00f46ff66c2ff389', '9d64bf0e2f6faa48')
    AND rc.year = {year}
    AND rc.month = {month}
    AND rc.day = {day}
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 17, 18, 19, 20, 21
