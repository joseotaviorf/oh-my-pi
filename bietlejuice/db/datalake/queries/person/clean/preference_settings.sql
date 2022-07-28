SELECT
    id,
    person_id AS id_person,
    timezone,
    language,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.preference_settings
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}