SELECT
  id AS id_question,
  survey_id AS id_survey,
  type,
  question,
  introduction,
  answer_choices,
  workspace_name,
  dt_load,
  year,
  month,
  day
FROM
  datalake_survicate_raw.survey_questions
WHERE
  year = {year}
  AND month = {month}
  AND day = {day}
