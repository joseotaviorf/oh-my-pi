SELECT
    response_uuid AS id_answer,
    id AS id_survey,
    PARSE_URL(page_url, 'QUERY', 'contractid') AS id_contract,
    PARSE_URL(page_url, 'QUERY', 'ticket_id') AS id_ticket,
    PARSE_URL(page_url, 'QUERY', 'email') AS email,
    CASE
      WHEN id  = '8214bf6281ffdb53' THEN 'owner'
      WHEN id = '0d7587def9ac6325' THEN 'tenant'
    END AS respondent_type,
    'keys' AS service_type,
    CASE
      WHEN id  = '8214bf6281ffdb53' THEN 'offboarding'
      WHEN id = '0d7587def9ac6325' THEN 'onboarding'
    END AS survey_type,
    'survicate' AS survey_source,
    answers[1].content AS improvement_tags,
    answers[2].content AS user_comment,
    CAST(answers[0].content AS INT) AS satisfaction_rating,
    "satisfaction evaluation" AS score_description,
    custom_attributes,
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
    AND id IN ('8214bf6281ffdb53', '0d7587def9ac6325')
UNION ALL
SELECT
    NULL AS id_answer,
    NULL AS id_survey,
    NULL AS id_contract,
    NULL AS id_ticket,
    NULL AS email,
    'tenant' AS respondent_type,
    'keys' AS service_type,
    'onboarding' AS survey_type,
    'gsheet' AS survey_source,
    improvement_tags,
    comments AS user_comment,
    score AS satisfaction_rating,
    "satisfaction evaluation" AS score_description,
    NULL AS custom_attributes,
    ts_input AS ts_first_seen,
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
    NULL AS id_contract,
    NULL AS id_ticket,
    NULL AS email,
    'owner' AS respondent_type,
    'keys' AS service_type,
    'offboarding' AS survey_type,
    'gsheet' AS survey_source,
    improvement_tags,
    comments AS user_comment,
    score AS satisfaction_rating,
    "satisfaction evaluation" AS score_description,
    NULL AS custom_attributes,
    ts_input AS ts_first_seen,
    ts_input AS ts_first_response,
    YEAR(ts_input) AS year,
    MONTH(ts_input) AS month,
    DAY(ts_input) AS day
FROM
    datalake_gsheets_clean.owner_offboarding_keys_csat
WHERE
    DATE(ts_input) = DATE('{year}-{month}-{day}')
