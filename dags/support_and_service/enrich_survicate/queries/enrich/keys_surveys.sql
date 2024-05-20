SELECT
    rc.id_response AS id_answer,
    sr.id_survey,
    sr.id_respondent,
    PARSE_URL(sr.response_url, 'QUERY', 'contractid') AS id_contract,
    PARSE_URL(sr.response_url, 'QUERY', 'ticket_id') AS id_ticket,
    PARSE_URL(sr.response_url, 'QUERY', 'email') AS email,
    sr.survey_name,
    CASE
        WHEN sr.id_survey = '8214bf6281ffdb53' THEN 'owner'
        WHEN sr.id_survey = '0d7587def9ac6325' THEN 'tenant'
    END AS respondent_type,
    'keys' AS service_type,
    CASE
        WHEN sr.id_survey = '8214bf6281ffdb53' THEN 'offboarding'
        WHEN sr.id_survey = '0d7587def9ac6325' THEN 'onboarding'
    END AS survey_type,
    'survicate' AS survey_source,
    CAST(COLLECT_LIST(rc.answer_content) FILTER (WHERE rc.id_question IN (1232189, 1241309)) AS STRING) AS improvement_tags,
    LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1232194, 1241310)) AS user_comment,
    CAST(LAST(rc.answer_content) FILTER (WHERE rc.id_question IN (1241308, 1232172)) AS INT) AS satisfaction_rating,
    "satisfaction evaluation" AS score_description,
    rc.ts_collected AS ts_first_response,
    rc.year,
    rc.month,
    rc.day
FROM
    datalake_survicate.response_content AS rc
JOIN
    datalake_survicate.survey_responses AS sr
        ON sr.id_response = rc.id_response
WHERE
    sr.id_survey IN ('8214bf6281ffdb53', '0d7587def9ac6325')
    AND rc.year = {year}
    AND rc.month = {month}
    AND rc.day = {day}
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 15, 16, 17, 18, 19
UNION ALL
SELECT
    NULL AS id_answer,
    NULL AS id_survey,
    NULL AS id_respondent,
    NULL AS id_contract,
    NULL AS id_ticket,
    NULL AS email,
    NULL AS survey_name,
    'tenant' AS respondent_type,
    'keys' AS service_type,
    'onboarding' AS survey_type,
    'gsheet' AS survey_source,
    improvement_tags,
    comments AS user_comment,
    score AS satisfaction_rating,
    "satisfaction evaluation" AS score_description,
    ts_input AS ts_first_response,
    YEAR(ts_input) AS year,
    MONTH(ts_input) AS month,
    DAY(ts_input) AS day
FROM
    datalake_gsheets_clean.tenant_onboarding_keys_csat
WHERE
    DATE(ts_input) = DATE('{year}-{month}-{day}')
UNION ALL
SELECT
    NULL AS id_answer,
    NULL AS id_survey,
    NULL AS id_respondent,
    NULL AS id_contract,
    NULL AS id_ticket,
    NULL AS email,
    NULL AS survey_name,
    'owner' AS respondent_type,
    'keys' AS service_type,
    'offboarding' AS survey_type,
    'gsheet' AS survey_source,
    improvement_tags,
    comments AS user_comment,
    score AS satisfaction_rating,
    "satisfaction evaluation" AS score_description,
    ts_input AS ts_first_response,
    YEAR(ts_input) AS year,
    MONTH(ts_input) AS month,
    DAY(ts_input) AS day
FROM
    datalake_gsheets_clean.owner_offboarding_keys_csat
WHERE
    DATE(ts_input) = DATE('{year}-{month}-{day}')
