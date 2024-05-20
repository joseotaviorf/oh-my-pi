WITH explode_parse_url AS (
  SELECT
    id_response,
    id_survey,
    id_respondent,
    EXPLODE(SPLIT(PARSE_URL(sr.response_url, 'QUERY'), '&')) AS parse,
    sr.survey_name
  FROM
    datalake_survicate.survey_responses AS sr
  WHERE
    sr.year = {year}
    AND sr.month = {month}
    AND sr.day = {day}
),
zendesk_tickets AS (
  SELECT DISTINCT
    id_response,
    id_survey,
    id_respondent,
    SPLIT(parse, '=')[1] AS id_ticket,
    survey_name
  FROM
    explode_parse_url
  WHERE
    SPLIT(parse, '=')[0] LIKE "%ticket_id%"
    OR SPLIT(parse, '=')[0] IN ("t_id", "id_ticket")
)
SELECT
  sr.id_survey,
  CAST(sr.id_ticket AS BIGINT) AS id_ticket,
  sr.id_respondent AS id_visitor,
  rc.id_response AS response_uuid,
  sr.id_respondent AS visitor_uuid,
  sr.survey_name,
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
  datalake_survicate.response_content AS rc
JOIN
  zendesk_tickets AS sr
    ON sr.id_response = rc.id_response
WHERE
  rc.year = {year}
  AND rc.month = {month}
  AND rc.day = {day}
GROUP BY 1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14
