SELECT
    response_uuid AS id_response,
    id_survey,
    GET_JSON_OBJECT(respondent, "$.uuid") AS id_respondent,
    url AS response_url,
    device_type,
    operating_system,
    CASE
        WHEN language = '' THEN NULL
        ELSE language
    END AS language,
    ts_collected,
    dt_load,
    year,
    month,
    day
FROM
    datalake_survicate_clean.survey_responses
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}