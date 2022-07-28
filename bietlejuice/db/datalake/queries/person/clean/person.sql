SELECT
    id,
    personuuid AS uuid_person,
    name AS person_name,
    gender,
    version,
    birth_date AS dt_birth,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.person
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}