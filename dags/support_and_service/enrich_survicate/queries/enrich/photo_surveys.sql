SELECT
    response_uuid AS id_response,
    s.id AS id_survey,
    PARSE_URL(page_url, 'QUERY', 'sk_owner') AS id_owner,
    'OWNER' AS respondent_type,
    'photos' AS service_type,
    'listing' AS service_context,
    'survicate' AS survey_source,
    answers[1].content AS improvement_tags,
    answers[2].content AS user_comment,
    CAST(answers[0].content AS INT) AS satisfaction_rating,
    "satisfaction evaluation" AS score_description,
    s.custom_attributes,
    ts_first_seen,
    ts_first_response,
    year,
    month,
    day
FROM
    datalake_survicate_clean.surveys AS s
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
    AND id = '46a1af7804f7a9ac'