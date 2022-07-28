SELECT
    personuuid AS uuid_person,
    rev,
    TO_TIMESTAMP(revtstmp/1000) AS ts_created,
    year,
    month,
    day
FROM
    datalake_person_raw.revinfo
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}