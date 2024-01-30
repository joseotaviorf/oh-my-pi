WITH rev_info_with_timestamp as (
    SELECT
        rev,
        CAST(FROM_UNIXTIME(CAST(revtstmp AS BIGINT)/1000) AS TIMESTAMP) AS ts_created
    FROM
        datalake_signatures_raw.revinfo
)
SELECT
    rev,
    ts_created,
    year(ts_created) AS year,
    month(ts_created) AS month,
    day(ts_created) AS day
FROM
    rev_info_with_timestamp
WHERE
    date(ts_created) = date('{year}-{month}-{day}')