WITH explode_parse_url AS (
  SELECT
    id_response,
    id_survey,
    id_respondent,
    sr.response_url,
    IF(REGEXP_EXTRACT(response_url,'case_id=([A-Za-z0-9]{{15,18}})') = '', NULL, REGEXP_EXTRACT(response_url,'case_id=([A-Za-z0-9]{{15,18}})')) AS id_case,
    IF(REGEXP_EXTRACT(response_url,'account_id=([A-Za-z0-9]{{15,18}})') = '', NULL, REGEXP_EXTRACT(response_url,'account_id=([A-Za-z0-9]{{15,18}})')) AS id_account,
    sr.survey_name
  FROM
    datalake_survicate.survey_responses AS sr
  WHERE
    sr.dt_load BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
salesforce_surveys AS (
  SELECT DISTINCT
    id_response,
    id_survey,
    id_respondent,
    id_case,
    id_account,
    survey_name
  FROM
    explode_parse_url
  WHERE
    id_case IS NOT NULL
)
SELECT
  ss.id_survey,
  ss.id_case,
  ss.id_account,
  rc.id_response AS response_uuid,
  ss.id_respondent,
  ss.survey_name,
  LAST(rc.answer_content) FILTER (WHERE rc.question_type IN ("text")) AS user_comment,
  CAST(LAST(
    CASE
      WHEN answer_content = 'Extremely happy' THEN 5
      WHEN answer_content = 'Happy' THEN 4
      WHEN answer_content = 'Neutral' THEN 3
      WHEN answer_content = 'Unsatisfied' THEN 2
      WHEN answer_content = 'Extremely unsatisfied' THEN 1
      ELSE answer_content
    END
  ) FILTER (WHERE rc.question_type IN ('rating', 'smiley_scale')) AS INT) AS csat_score,
  LOWER(LAST(rc.answer_content) FILTER (WHERE rc.question_type IN ("single"))) IN ('sim', "si", "sí") AS is_solved,
  rc.ts_collected AS ts_first_response,
  rc.dt_load,
  rc.year,
  rc.month,
  rc.day
FROM
  salesforce_surveys AS ss
LEFT JOIN datalake_survicate.response_content AS rc
    ON ss.id_response = rc.id_response
WHERE
  MAKE_DATE(rc.year, rc.month, rc.day) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
GROUP BY 1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14
