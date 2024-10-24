SELECT
    uuid AS response_uuid,
    survey_id AS id_survey,
    url,
    device_type,
    operating_system,
    language,
    answers,
    respondent,
    workspace_name,
    TIMESTAMP(collected_at) AS ts_collected,
    DATE(dt_load) AS dt_load,
    INT(year) AS year,
    INT(month) AS month,
    INT(day) AS day
FROM
    datalake_survicate_raw.survey_responses
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
