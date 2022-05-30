SELECT
    id,
    person_id AS id_person,
    country,
    state,
    city,
    neighborhood,
    address,
    zip_code,
    complement,
    number,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_person_raw.address
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
