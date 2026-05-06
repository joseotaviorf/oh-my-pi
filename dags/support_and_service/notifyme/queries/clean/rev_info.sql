SELECT
    CAST(rev AS BIGINT) AS rev,
    CAST(revtstmp AS TIMESTAMP) AS ts_revision,
    YEAR(CAST(revtstmp AS TIMESTAMP)) AS year,
    MONTH(CAST(revtstmp AS TIMESTAMP)) AS month,
    DAY(CAST(revtstmp AS TIMESTAMP)) AS day
FROM datalake_notifyme_raw.revinfo
