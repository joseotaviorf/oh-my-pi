SELECT
    s.response_uuid AS id_answer,
    s.id AS id_survey,
    CASE
      WHEN s.answers[0]['content'] NOT IN ('1', '2', '3', '4', '5') THEN s.answers[0]['content']
    END AS respondent_type,
    'keys' AS service_type,
    'lockbox' AS service_context,
    'survicate' AS source_name,
    CASE
      WHEN s.ts_first_response < DATE('2022-11-16') THEN s.answers[1]['content']
      ELSE s.answers[2]['content']
    END AS improvement_tags,
    CASE
      WHEN s.ts_first_response < DATE('2022-11-16') THEN s.answers[2]['content']
    END AS respondent_comments,
    CAST(
      CASE
        WHEN s.ts_first_response < DATE('2022-11-16') THEN s.answers[0]['content']
        ELSE s.answers[1]['content']
      END
    AS INTEGER) AS satisfaction_score,
    "satisfaction evaluation" AS score_description,
    s.custom_attributes,
    s.ts_first_seen,
    s.ts_first_response AS ts_submitted,
    s.year,
    s.month,
    s.day
FROM
    datalake_survicate_clean.surveys AS s
WHERE
    id IN ('efe52808bddcd15f')
    AND s.year = {year}
    AND s.month = {month}
    AND s.day = {day}