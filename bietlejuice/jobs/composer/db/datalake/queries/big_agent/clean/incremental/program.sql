SELECT
    id,
    name,
    code,
    details,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.program
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}