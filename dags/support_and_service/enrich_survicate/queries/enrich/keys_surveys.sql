SELECT
  PARSE_URL(page_url, 'QUERY', 'contractid') AS id_contract,
  PARSE_URL(page_url, 'QUERY', 'email') AS email,
  CAST(answers[0].content AS INT) AS satisfaction_rating,
  answers[1].content AS improvement_tags,
  CASE
    WHEN id  = '8214bf6281ffdb53' THEN 'Offboarding'
    WHEN id = '0d7587def9ac6325' THEN 'Onboarding'
  END AS survey_type,
  'survicate' AS survey_source,
  answers[2].content AS user_comment,
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
  NULL AS id_contract,
  NULL AS email,
  score AS satisfaction_rating,
  improvement_tags,
  'Onboarding' AS survey_type,
  'gsheet' AS survey_source,
  comments AS user_comment,
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
  NULL AS id_contract,
  NULL AS email,
  score AS satisfaction_rating,
  improvement_tags,
  'Offboarding' AS survey_type,
  'gsheet' AS survey_source,
  comments AS user_comment,
  ts_input AS ts_first_seen,
  ts_input AS ts_first_response,
  YEAR(ts_input) AS year,
  MONTH(ts_input) AS month,
  DAY(ts_input) AS day
FROM 
  datalake_gsheets_clean.owner_offboarding_keys_csat
WHERE
  DATE(ts_input) = DATE('{year}-{month}-{day}')
