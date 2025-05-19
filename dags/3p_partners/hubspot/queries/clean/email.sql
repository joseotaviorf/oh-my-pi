SELECT
    id AS id_email,
    properties,
    properties_with_history,
    associations,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hubspot_raw.email
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
