SELECT
    rev,
    CAST(FROM_UNIXTIME(CAST(revtstmp AS BIGINT)/1000) AS TIMESTAMP) AS ts_created,
    year,
    month,
    day
FROM
    datalake_bob_raw.revinfo
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}