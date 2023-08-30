SELECT
  id AS id_survey,
  CAST(COALESCE(custom_attributes.ticket_id, PARSE_URL(page_url, 'QUERY', 't_id')) AS BIGINT) AS id_ticket,
  id_visitor,
  response_uuid,
  visitor_uuid,
  answers[2].content AS user_comment,
  CASE
    WHEN answers[1].survey_point.pretty_type = 'Smiley scale' AND answers[1].content = 'Extremely happy' THEN 5
    WHEN answers[1].survey_point.pretty_type = 'Smiley scale' AND answers[1].content = 'Happy' THEN 4
    WHEN answers[1].survey_point.pretty_type = 'Smiley scale' AND answers[1].content = 'Neutral' THEN 3
    WHEN answers[1].survey_point.pretty_type = 'Smiley scale' AND answers[1].content = 'Unsatisfied' THEN 2
    WHEN answers[1].survey_point.pretty_type = 'Smiley scale' AND answers[1].content = 'Extremely unsatisfied' THEN 1
    ELSE CAST(answers[1].content AS INT)
  END AS csat_score,
  LOWER(answers[0].content) = 'sim' AS is_solved,
  ts_first_seen,
  ts_first_response,
  year,
  month,
  day
FROM
  datalake_survicate_clean.surveys
WHERE
  (
    custom_attributes.ticket_id IS NOT NULL
    OR PARSE_URL(page_url, 'QUERY', 't_id') IS NOT NULL
  )
  AND year = {year}
  AND month = {month}
  AND day = {day}
