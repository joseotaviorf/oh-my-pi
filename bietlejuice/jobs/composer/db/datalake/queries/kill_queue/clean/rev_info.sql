SELECT
    CAST(rev AS BIGINT) AS rev,
    CAST(revtstmp AS BIGINT) AS ts_rev,
    year,
    month,
    day
FROM
    datalake_kill_queue_raw.revinfo
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}