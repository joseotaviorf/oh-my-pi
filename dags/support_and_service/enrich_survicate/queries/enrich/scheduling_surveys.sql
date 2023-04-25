SELECT
    s.response_uuid AS id_answer,
    s.id AS id_survey,
    PARSE_URL(s.page_url, 'QUERY', 'contractid') AS id_contract,
    CASE
      WHEN s.id = 'b1133bc4925426d0' THEN 'owner'
      WHEN s.id = '278f21b367c2344c' THEN 'tenant'
    END AS respondent_type,
    'RSS' AS service_type,
    CASE
      WHEN s.id = 'b1133bc4925426d0' THEN 'onboarding'
      WHEN s.id = '278f21b367c2344c' THEN 'offboarding'
    END AS service_context,
    'survicate' AS source_name,
    s.answers[1]['content'] AS improvement_tags,
    s.answers[2]['content'] AS respondent_comments,
    CAST(s.answers[0]['content'] AS INTEGER) AS satisfaction_score,
    'satisfaction evaluation' AS score_description,
    s.custom_attributes,
    s.ts_first_seen,
    s.ts_first_response AS ts_submitted,
    s.year,
    s.month,
    s.day
FROM
    datalake_survicate_clean.surveys AS s
WHERE
    id IN ('b1133bc4925426d0', '278f21b367c2344c')
    AND s.year = {year}
    AND s.month = {month}
    AND s.day = {day}
