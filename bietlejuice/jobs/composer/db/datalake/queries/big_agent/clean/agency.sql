SELECT
    id,
    house_id AS id_house,
    enrollment_id AS id_enrollment,
    details,
    since AS dt_since,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.agency
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}