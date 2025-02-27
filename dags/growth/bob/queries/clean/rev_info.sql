SELECT
    rev,
    CAST(FROM_UNIXTIME(CAST(revtstmp AS BIGINT)/1000) AS TIMESTAMP) AS ts_created,
    YEAR(ts_created) AS year,
    MONTH(ts_created) AS month,
    DAY(ts_created) as day
FROM
    datalake_bob_raw.revinfo
