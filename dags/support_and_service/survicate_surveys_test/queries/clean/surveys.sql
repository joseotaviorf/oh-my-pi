SELECT
    id AS id_survey,
    name AS survey_name,
    type,
    launch,
    CAST(responses AS BIGINT) AS total_responses,
    CAST(enabled AS BOOLEAN) AS is_enabled,
    workspace_name,
    TIMESTAMP(created_at) AS ts_created,
    DATE(dt_load) AS dt_load,
    INT(year) AS year,
    INT(month) AS month,
    INT(day) AS day
FROM
    datalake_survicate_test_raw.surveys
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
