SELECT
    response_uuid AS id_response,
    PARSE_URL(page_url, 'QUERY', 'sk_owner') AS id_owner,
    CAST(answers[0].content AS INT) AS satisfaction_rating,
    answers[1].content AS improvement_tags,
    answers[2].content AS user_comment,
    'survicate' AS survey_source,
    ts_first_seen,
    ts_first_response,
    year,
    month,
    day
FROM 
    datalake_survicate_clean.surveys
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
    AND id = '46a1af7804f7a9ac'