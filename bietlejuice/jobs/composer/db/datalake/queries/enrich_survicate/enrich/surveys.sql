SELECT
  id AS id_survey,
  custom_attributes.ticket_id AS id_ticket,
  id_visitor,
  response_uuid,
  visitor_uuid,
  answers[2].content AS user_comment,
  CAST(answers[1].content AS INT) AS csat_score,
  LOWER(answers[0].content) = 'sim' AS is_solved,
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
