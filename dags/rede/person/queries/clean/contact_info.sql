SELECT
    id,
    person_id AS id_person,
    contact_info,
    category,
    contact_preferences,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.contact_info
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
