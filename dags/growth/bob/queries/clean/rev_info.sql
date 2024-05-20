SELECT
    rev,
    CAST(FROM_UNIXTIME(CAST(revtstmp AS BIGINT)/1000) AS TIMESTAMP) AS ts_created,
    year,
    month,
    day
FROM
    datalake_bob_raw.revinfo
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
