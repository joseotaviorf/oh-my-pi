SELECT
    CAST(id AS BIGINT) AS id_attribute,
    respondent_uuid,
    name,
    value,
    workspace_name,
    DATE(dt_load) AS dt_load,
    INT(year) AS year,
    INT(month) AS month,
    INT(day) AS day
FROM
    datalake_survicate_test_raw.respondent_attributes
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
