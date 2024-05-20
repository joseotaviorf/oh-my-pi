SELECT
    sr.response_uuid AS id_response,
    sr.id_survey,
    GET_JSON_OBJECT(sr.respondent, "$.uuid") AS id_respondent,
    s.survey_name,
    sr.url AS response_url,
    sr.device_type,
    sr.operating_system,
    CASE
        WHEN sr.language = '' THEN NULL
        ELSE sr.language
    END AS language,
    sr.ts_collected,
    sr.dt_load,
    sr.year,
    sr.month,
    sr.day
FROM
    datalake_survicate_clean.survey_responses AS sr
LEFT JOIN
    datalake_survicate_clean.surveys AS s
        ON sr.id_survey = s.id_survey
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}