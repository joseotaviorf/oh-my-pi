SELECT
    s.response_uuid AS id_answer,
    s.id AS id_survey,
    PARSE_URL(s.page_url, 'QUERY', 't_id') AS id_ticket,
    PARSE_URL(s.page_url, 'QUERY', 'email') AS respondent_email,
    CASE
        WHEN s.id = '01176589bb5ad239' THEN "owner"
        WHEN s.id = 'a514a5d6fe646931' THEN "tenant"
    END AS respondent_type,
    'repairs' AS service_type,
    'offboarding' AS service_context,
    'survicate' AS source_name,
    s.answers[2]['content'] AS improvement_tags,
    s.answers[3]['content'] AS respondent_comments,
    s.answers[1]['content'] AS satisfaction_score,
    "satisfaction evaluation" AS score_description,
    s.answers[0]['content'] AS secondary_satisfaction_score,
    "satisfaction between parties involved" AS secondary_score_description,
    s.custom_attributes,
    s.ts_first_seen,
    s.ts_first_response AS ts_submitted,
    s.year,
    s.month,
    s.day
FROM
    datalake_survicate_clean.surveys AS s
WHERE
    id IN ('a514a5d6fe646931', '01176589bb5ad239')
    AND s.year = {year}
    AND s.month = {month}
    AND s.day = {day}
