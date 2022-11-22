SELECT
    id,
    display_name,
    first_name,
    last_name,
    email,
    year,
    month,
    day
FROM
    datalake_looker_raw.users
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
