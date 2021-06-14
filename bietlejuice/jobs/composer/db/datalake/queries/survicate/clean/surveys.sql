SELECT
    id,
    visitor_id AS id_visitor,
    response_uuid,
    visitor_uuid,
    custom_attributes,
    answers,
    page_url,
    CAST(first_seen_date AS TIMESTAMP) AS ts_first_seen,
    CAST(first_response_date AS TIMESTAMP) AS ts_first_response,
    year,
    month,
    day
FROM
    datalake_survicate_raw.surveys
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
