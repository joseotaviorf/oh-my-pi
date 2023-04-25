SELECT DISTINCT
    s.response_uuid AS id_answer,
    s.id AS id_survey,
    PARSE_URL(s.page_url, 'QUERY', 'contractid') AS id_contract,
    c.id_user AS id_respondent,
    "owner" AS respondent_type,
    'inspections' AS service_type,
    'offboarding' AS service_context,
    'survicate' AS source_name,
    s.answers[2]['content'] AS improvement_tags,
    s.answers[3]['content'] AS respondent_comments,
    s.answers[1]['content'] AS satisfaction_score,
    "satisfaction evaluation" AS score_description,
    s.answers[0]['content'] AS secondary_satisfaction_score,
    "house satisfaction" AS secondary_score_description,
    s.custom_attributes,
    s.ts_first_seen,
    s.ts_first_response AS ts_submitted,
    s.year,
    s.month,
    s.day
FROM
    datalake_survicate_clean.surveys AS s
LEFT JOIN
    datalake_ebdb_clean.contract AS c
        ON c.id = PARSE_URL(s.page_url, 'QUERY', 'contractid')
WHERE
    s.id = '00f46ff66c2ff389'
    AND s.year = {year}
    AND s.month = {month}
    AND s.day = {day}
